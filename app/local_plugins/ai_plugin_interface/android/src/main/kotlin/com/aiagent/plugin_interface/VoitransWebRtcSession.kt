package com.aiagent.plugin_interface

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import org.webrtc.*

/**
 * VoiTrans 平台 WebRTC 连接会话（共享类）
 *
 * 封装完整的连接流程：
 *   1. HTTP POST /open/v1/agents/{agentId}/connect → token
 *   2. WebRTC PeerConnection 创建 + SDP offer
 *   3. HTTP POST /api/offer → SDP answer
 *   4. ICE candidate 交换
 *   5. DataChannel 事件监听
 *
 * StsAssistantService / AstAssistantService 各自实现 EventListener 解析不同事件。
 */
class VoitransWebRtcSession(private val context: Context) {

    companion object {
        private const val TAG = "VoitransWebRtc"
        private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()
        private var factoryInitialized = false
        private var peerConnectionFactory: PeerConnectionFactory? = null
        private var factoryInitJob: kotlinx.coroutines.Job? = null

        @Synchronized
        private fun ensureFactory(context: Context) {
            if (factoryInitialized) return
            val startMs = System.currentTimeMillis()
            PeerConnectionFactory.initialize(
                PeerConnectionFactory.InitializationOptions.builder(context.applicationContext)
                    .setEnableInternalTracer(false)
                    .createInitializationOptions()
            )
            peerConnectionFactory = PeerConnectionFactory.builder()
                .setAudioDeviceModule(
                    org.webrtc.audio.JavaAudioDeviceModule.builder(context.applicationContext)
                        .setUseHardwareAcousticEchoCanceler(true)
                        .setUseHardwareNoiseSuppressor(true)
                        .createAudioDeviceModule()
                )
                .createPeerConnectionFactory()
            factoryInitialized = true
            Log.d(TAG, "PeerConnectionFactory initialized in ${System.currentTimeMillis() - startMs}ms")
        }

        /**
         * 预初始化 PeerConnectionFactory（在 App 启动时调用，避免首次连接卡顿）
         */
        fun warmup(context: Context) {
            if (factoryInitialized) return
            factoryInitJob = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO)
                .launch {
                    ensureFactory(context)
                }
        }

        /** 全局共享 OkHttpClient（连接池复用，减少 TLS 握手） */
        val sharedHttpClient: OkHttpClient by lazy {
            OkHttpClient.Builder()
                .connectTimeout(java.time.Duration.ofSeconds(10))
                .readTimeout(java.time.Duration.ofSeconds(10))
                .connectionPool(okhttp3.ConnectionPool(4, 2, java.util.concurrent.TimeUnit.MINUTES))
                .build()
        }

        /**
         * 预热 HTTP 连接池（DNS + TLS 握手提前完成）
         */
        fun warmupHttp(baseUrl: String) {
            kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
                try {
                    val url = baseUrl.trimEnd('/') + "/open/v1/agents"
                    val req = Request.Builder().url(url).head().build()
                    sharedHttpClient.newCall(req).execute().close()
                    Log.d(TAG, "HTTP connection pool warmed up for $baseUrl")
                } catch (e: Exception) {
                    Log.d(TAG, "HTTP warmup failed (non-fatal): ${e.message}")
                }
            }
        }
    }

    interface EventListener {
        fun onConnected()
        fun onMessage(json: JSONObject)
        fun onDisconnected()
        fun onError(code: String, message: String)
    }

    // 配置
    private var baseUrl = ""
    private var appId = ""
    private var appSecret = ""
    private var agentId = ""

    // WebRTC
    private var peerConnection: PeerConnection? = null
    private var localAudioTrack: AudioTrack? = null
    private var dataChannel: DataChannel? = null
    private var pcId: String? = null

    // 状态
    private var listener: EventListener? = null
    private val httpClient get() = sharedHttpClient
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val pendingCandidates = mutableListOf<IceCandidate>()
    @Volatile private var remoteDescriptionSet = false
    private var pingJob: kotlinx.coroutines.Job? = null

    fun initialize(baseUrl: String, appId: String, appSecret: String, agentId: String) {
        this.baseUrl = baseUrl.trimEnd('/')
        this.appId = appId
        this.appSecret = appSecret
        this.agentId = agentId
    }

    /**
     * 建立 WebRTC 连接（阻塞调用，应在协程中执行）
     *
     * Token 请求与 WebRTC PeerConnection 创建并行执行，减少总耗时。
     */
    fun connect(listener: EventListener) {
        this.listener = listener
        val totalStart = System.currentTimeMillis()

        try {
            // 1. 并行：获取 Token + 初始化 WebRTC Factory / PeerConnection
            Log.d(TAG, "Requesting connect token for agent=$agentId")
            val tokenFuture = java.util.concurrent.CompletableFuture.supplyAsync {
                requestConnectToken()
            }

            // 等待预初始化完成（如果 warmup 已经在后台跑了）
            kotlinx.coroutines.runBlocking { factoryInitJob?.join() }
            ensureFactory(context)

            // 2. 创建 PeerConnection + 本地音频 + SDP offer（不依赖 token，与 token 请求并行）
            //    注意：不要在此处调用 setCommunicationDevice()，会和 JavaAudioDeviceModule 冲突
            createPeerConnection()
            createLocalAudioTrack()
            val offer = createOffer()
            Log.d(TAG, "SDP offer created in ${System.currentTimeMillis() - totalStart}ms")

            // 3. 等待 token 请求完成
            val connectResp = tokenFuture.get(10, java.util.concurrent.TimeUnit.SECONDS)
            val rawConnectUrl = connectResp.getString("connect_url")
            val connectUrl = if (rawConnectUrl.startsWith("http://")) {
                rawConnectUrl.replaceFirst("http://", "https://")
            } else {
                rawConnectUrl
            }
            val connectToken = connectResp.getString("token")
            Log.d(TAG, "Got connect token in ${System.currentTimeMillis() - totalStart}ms, url=$connectUrl")

            // 4. 发送 offer 到服务端
            val answer = sendOffer(connectUrl, offer, connectToken)
            pcId = answer.getString("pc_id")
            Log.d(TAG, "Got SDP answer in ${System.currentTimeMillis() - totalStart}ms, pc_id=$pcId")

            // 5. 设置 remote description
            val answerSdp = SessionDescription(
                SessionDescription.Type.ANSWER,
                answer.getString("sdp")
            )
            setRemoteDescription(answerSdp)

            // 6. 发送缓存的 ICE candidates
            flushPendingCandidates()

            Log.d(TAG, "Connect completed in ${System.currentTimeMillis() - totalStart}ms")

        } catch (e: Exception) {
            Log.e(TAG, "Connect failed after ${System.currentTimeMillis() - totalStart}ms", e)
            listener.onError("connect_failed", e.message ?: "Unknown error")
        }
    }

    fun startAudio() {
        localAudioTrack?.setEnabled(true)
        Log.d(TAG, "Audio started")
    }

    fun stopAudio() {
        localAudioTrack?.setEnabled(false)
        Log.d(TAG, "Audio stopped")
    }

    // ── DataChannel ping 心跳 ──

    /** 启动 ping 心跳：每 1 秒发一次纯文本 "ping"，服务端用它作为存活判断。 */
    private fun startPingHeartbeat() {
        if (pingJob?.isActive == true) return
        pingJob = scope.launch {
            while (isActive) {
                val dc = dataChannel
                if (dc != null && dc.state() == DataChannel.State.OPEN) {
                    try {
                        val buf = java.nio.ByteBuffer.wrap("ping".toByteArray(Charsets.UTF_8))
                        dc.send(DataChannel.Buffer(buf, false))
                    } catch (e: Exception) {
                        Log.w(TAG, "ping send failed", e)
                    }
                }
                delay(1000)
            }
        }
        Log.d(TAG, "ping heartbeat started")
    }

    private fun stopPingHeartbeat() {
        pingJob?.cancel()
        pingJob = null
    }

    /**
     * 通过 DataChannel 发送 JSON 控制消息
     */
    fun sendDataChannelMessage(json: JSONObject) {
        val dc = dataChannel
        if (dc == null || dc.state() != DataChannel.State.OPEN) {
            Log.w(TAG, "DataChannel not open (state=${dc?.state()}), drop: ${json.toString().take(100)}")
            return
        }
        val bytes = json.toString().toByteArray(Charsets.UTF_8)
        val buf = java.nio.ByteBuffer.wrap(bytes)
        dc.send(DataChannel.Buffer(buf, false))
        Log.d(TAG, "DC → ${json.toString().take(120)}")
    }

    fun release() {
        scope.launch {
            // 断开服务端会话
            val id = pcId
            if (id != null) {
                try {
                    // pc_id 可能包含 '#' 等特殊字符（如 "SmallWebRTCConnection#3-xxxx"），
                    // 不能直接拼字符串，否则 OkHttp 会把 '#' 之后当作 URL fragment 丢弃。
                    // 使用 HttpUrl.Builder.addPathSegment 让 OkHttp 正确百分号编码。
                    val url = baseUrl.toHttpUrl().newBuilder()
                        .addPathSegment("api")
                        .addPathSegment("sessions")
                        .addPathSegment(id)
                        .build()
                    val req = Request.Builder()
                        .url(url)
                        .delete()
                        .build()
                    httpClient.newCall(req).execute().close()
                    Log.d(TAG, "Session $id deleted")
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to delete session", e)
                }
            }
        }

        // 停 ping 心跳
        stopPingHeartbeat()

        // 关闭 WebRTC 资源
        try {
            dataChannel?.close()
            dataChannel = null
            localAudioTrack?.setEnabled(false)
            localAudioTrack = null
            peerConnection?.close()
            peerConnection = null
        } catch (e: Exception) {
            Log.w(TAG, "Release error", e)
        }

        listener?.onDisconnected()
        listener = null
        scope.cancel()
    }

    // ── HTTP: 获取连接 Token ──

    private fun requestConnectToken(): JSONObject {
        val url = "$baseUrl/open/v1/agents/$agentId/connect"
        val body = JSONObject().toString().toRequestBody(JSON_MEDIA)
        val req = Request.Builder()
            .url(url)
            .post(body)
            .addHeader("X-App-Id", appId)
            .addHeader("X-App-Secret", appSecret)
            .build()
        val resp = httpClient.newCall(req).execute()
        if (!resp.isSuccessful) {
            val errBody = resp.body?.string() ?: ""
            resp.close()
            throw Exception("Connect token request failed: ${resp.code} $errBody")
        }
        val json = JSONObject(resp.body!!.string())
        resp.close()
        return json
    }

    // ── HTTP: 发送 SDP Offer ──

    private fun sendOffer(connectUrl: String, offer: SessionDescription, token: String): JSONObject {
        val requestData = JSONObject().apply {
            put("connect_token", token)
            put("agent_id", agentId)
        }
        val payload = JSONObject().apply {
            put("sdp", offer.description)
            put("type", "offer")
            put("request_data", requestData)
        }
        val req = Request.Builder()
            .url(connectUrl)
            .post(payload.toString().toRequestBody(JSON_MEDIA))
            .build()
        val resp = httpClient.newCall(req).execute()
        if (!resp.isSuccessful) {
            val errBody = resp.body?.string() ?: ""
            resp.close()
            throw Exception("Offer request failed: ${resp.code} $errBody")
        }
        val json = JSONObject(resp.body!!.string())
        resp.close()
        return json
    }

    // ── HTTP: 发送 ICE Candidates ──

    private fun sendIceCandidates(candidates: List<IceCandidate>) {
        val id = pcId ?: return
        val arr = JSONArray()
        for (c in candidates) {
            arr.put(JSONObject().apply {
                put("candidate", c.sdp)
                put("sdp_mid", c.sdpMid)
                put("sdp_mline_index", c.sdpMLineIndex)
            })
        }
        val payload = JSONObject().apply {
            put("pc_id", id)
            put("candidates", arr)
        }
        val req = Request.Builder()
            .url("$baseUrl/api/offer")
            .patch(payload.toString().toRequestBody(JSON_MEDIA))
            .build()
        try {
            httpClient.newCall(req).execute().close()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to send ICE candidates", e)
        }
    }

    // ── WebRTC: PeerConnection ──

    private fun createPeerConnection() {
        val iceServers = listOf(
            PeerConnection.IceServer.builder("stun:stun.miwifi.com:3478").createIceServer(),
            PeerConnection.IceServer.builder("stun:stun.chat.bilibili.com:3478").createIceServer(),
            PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer(),
        )
        val rtcConfig = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
            // 必须 MAX_BUNDLE：audio / application(DataChannel) 共用同一个 ICE+DTLS transport，
            // 否则 DataChannel 的 m=application 会拿到独立 transport，我们 trickle ICE 只对单个
            // m-line 发 candidate，另一条永远起不来 → SCTP/DataChannel 永不 open。
            bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE
            rtcpMuxPolicy = PeerConnection.RtcpMuxPolicy.REQUIRE
        }

        peerConnection = peerConnectionFactory!!.createPeerConnection(rtcConfig, object : PeerConnection.Observer {
            override fun onIceCandidate(candidate: IceCandidate) {
                if (remoteDescriptionSet) {
                    scope.launch { sendIceCandidates(listOf(candidate)) }
                } else {
                    synchronized(pendingCandidates) {
                        pendingCandidates.add(candidate)
                    }
                }
            }

            override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) {
                Log.d(TAG, "ICE state: $state")
                when (state) {
                    PeerConnection.IceConnectionState.CONNECTED -> {
                        // WebRTC 连接建立后，使用 setSpeakerphoneOn 设置输出路由
                        // 不能用 setCommunicationDevice()，会触发设备变更导致 AudioRecord 中断
                        AudioOutputManager.applyModeForWebRtc()
                        listener?.onConnected()
                    }
                    PeerConnection.IceConnectionState.DISCONNECTED,
                    PeerConnection.IceConnectionState.FAILED,
                    PeerConnection.IceConnectionState.CLOSED -> listener?.onDisconnected()
                    else -> {}
                }
            }

            override fun onDataChannel(dc: DataChannel) {
                Log.d(TAG, "Remote DataChannel received: ${dc.label()}")
                setupDataChannel(dc)
            }

            override fun onSignalingChange(s: PeerConnection.SignalingState) {}
            override fun onIceConnectionReceivingChange(b: Boolean) {}
            override fun onIceGatheringChange(s: PeerConnection.IceGatheringState) {}
            override fun onIceCandidatesRemoved(c: Array<out IceCandidate>) {}
            override fun onAddStream(s: MediaStream) {}
            override fun onRemoveStream(s: MediaStream) {}
            override fun onRenegotiationNeeded() {}
            override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) {}
        }) ?: throw Exception("Failed to create PeerConnection")

        // 创建本地 DataChannel（服务端也可能推送）
        val dcInit = DataChannel.Init().apply {
            ordered = true
        }
        val dc = peerConnection!!.createDataChannel("events", dcInit)
        if (dc != null) {
            setupDataChannel(dc)
        }
    }

    private fun setupDataChannel(dc: DataChannel) {
        dataChannel = dc
        dc.registerObserver(object : DataChannel.Observer {
            override fun onBufferedAmountChange(amount: Long) {}

            override fun onStateChange() {
                val state = dc.state()
                Log.d(TAG, "DataChannel[${dc.label()}] state: $state")
                if (state == DataChannel.State.OPEN) {
                    // 服务端 is_connected() 依赖客户端每 3 秒内送达一次 "ping"。
                    // 没 ping → cleanup 会把连接当成 offline 销毁。
                    startPingHeartbeat()
                } else if (state == DataChannel.State.CLOSED ||
                           state == DataChannel.State.CLOSING) {
                    stopPingHeartbeat()
                }
            }

            override fun onMessage(buffer: DataChannel.Buffer) {
                if (buffer.binary) return
                val bytes = ByteArray(buffer.data.remaining())
                buffer.data.get(bytes)
                val text = String(bytes, Charsets.UTF_8)
                try {
                    val json = JSONObject(text)
                    listener?.onMessage(json)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to parse DataChannel message: $text", e)
                }
            }
        })
    }

    // ── WebRTC: Audio Track ──

    private fun createLocalAudioTrack() {
        val factory = peerConnectionFactory!!
        val audioSource = factory.createAudioSource(MediaConstraints())
        localAudioTrack = factory.createAudioTrack("audio_local", audioSource)
        localAudioTrack!!.setEnabled(false) // 初始不发送音频
        peerConnection!!.addTrack(localAudioTrack!!)
    }

    // ── WebRTC: SDP ──

    private fun createOffer(): SessionDescription {
        val latch = java.util.concurrent.CountDownLatch(1)
        var result: SessionDescription? = null
        var error: String? = null

        val constraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", "false"))
        }

        peerConnection!!.createOffer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription) {
                peerConnection!!.setLocalDescription(object : SdpObserver {
                    override fun onSetSuccess() {
                        result = sdp
                        latch.countDown()
                    }
                    override fun onSetFailure(msg: String) {
                        error = "setLocalDescription failed: $msg"
                        latch.countDown()
                    }
                    override fun onCreateSuccess(s: SessionDescription) {}
                    override fun onCreateFailure(s: String) {}
                }, sdp)
            }
            override fun onCreateFailure(msg: String) {
                error = "createOffer failed: $msg"
                latch.countDown()
            }
            override fun onSetSuccess() {}
            override fun onSetFailure(s: String) {}
        }, constraints)

        latch.await(10, java.util.concurrent.TimeUnit.SECONDS)
        if (error != null) throw Exception(error)
        return result ?: throw Exception("createOffer timeout")
    }

    private fun setRemoteDescription(sdp: SessionDescription) {
        val latch = java.util.concurrent.CountDownLatch(1)
        var error: String? = null

        peerConnection!!.setRemoteDescription(object : SdpObserver {
            override fun onSetSuccess() {
                remoteDescriptionSet = true
                latch.countDown()
            }
            override fun onSetFailure(msg: String) {
                error = "setRemoteDescription failed: $msg"
                latch.countDown()
            }
            override fun onCreateSuccess(s: SessionDescription) {}
            override fun onCreateFailure(s: String) {}
        }, sdp)

        latch.await(10, java.util.concurrent.TimeUnit.SECONDS)
        if (error != null) throw Exception(error)
    }

    private fun flushPendingCandidates() {
        val candidates: List<IceCandidate>
        synchronized(pendingCandidates) {
            candidates = pendingCandidates.toList()
            pendingCandidates.clear()
        }
        if (candidates.isNotEmpty()) {
            scope.launch { sendIceCandidates(candidates) }
        }
    }
}
