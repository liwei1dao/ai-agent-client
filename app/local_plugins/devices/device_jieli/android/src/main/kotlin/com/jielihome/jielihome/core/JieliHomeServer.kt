package com.jielihome.jielihome.core

import android.content.Context
import com.jieli.bluetooth.bean.BluetoothOption
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jieli.bluetooth.impl.rcsp.RCSPController
import com.jieli.bluetooth.interfaces.rcsp.ITwsOp
import com.jieli.bluetooth.utils.JL_Log
import com.jielihome.jielihome.api.JieliEventListener
import com.jielihome.jielihome.bridge.EventDispatcher
import com.jielihome.jielihome.event.BluetoothEventForwarder
import com.jielihome.jielihome.event.CustomEventForwarder
import com.jielihome.jielihome.event.DeviceInfoEventForwarder
import com.jielihome.jielihome.event.MediaEventForwarder
import com.jielihome.jielihome.feature.ConnectFeature
import com.jielihome.jielihome.feature.CustomCmdFeature
import com.jielihome.jielihome.feature.DeviceInfoFeature
import com.jielihome.jielihome.feature.ScanFeature
import com.jielihome.jielihome.feature.ota.OtaFeature
import com.jielihome.jielihome.feature.record.DeviceRecordFeature
import com.jielihome.jielihome.feature.translation.EventChannelAudioBridge
import com.jielihome.jielihome.feature.translation.TranslationAudioBridge
import com.jielihome.jielihome.feature.translation.TranslationFeature
import com.jielihome.jielihome.feature.voice.SpeechFeature

/**
 * 全局单例。原生层和 Flutter 层共用同一个 server。
 *
 * 原生用法：
 *   ```
 *   val server = JieliHomeServer.get()
 *   server.initialize(context, multiDevice = true, skipNoNameDev = false, enableLog = true)
 *   server.addEventListener(myListener)              // 订阅事件
 *   server.scanFeature.startScan(30_000)
 *   server.translationFeature.start(MODE_CALL_TRANSLATION, mapOf("address" to mac))
 *   server.translationFeature.feedTranslatedAudio("uplink", pcm, AudioFormat(), false)
 *   ```
 *
 * Flutter 侧由 [com.jielihome.jielihome.JielihomePlugin] 自动绑定 EventChannel + MethodChannel。
 * 即使没有 Flutter，原生也能完整使用 server。
 */
class JieliHomeServer private constructor() {

    companion object {
        @Volatile
        private var instance: JieliHomeServer? = null

        @JvmStatic
        fun get(): JieliHomeServer = instance ?: synchronized(this) {
            instance ?: JieliHomeServer().also { instance = it }
        }
    }

    @Volatile
    var initialized: Boolean = false
        private set

    /** 事件总线，原生层通过 [addEventListener] 订阅；Flutter 自动注入 EventChannel sink */
    val dispatcher: EventDispatcher = EventDispatcher()

    private lateinit var btManager: JL_BluetoothManager

    /** 模块内访问 btManager 用（如 [com.jielihome.jielihome.feature.assistant.JieliAssistantPort]
     *  需要直接持有 [com.jieli.bluetooth.impl.rcsp.record.RecordOpImpl] 单例时）。 */
    internal val internalBtManager: JL_BluetoothManager get() = btManager

    /**
     * 杰理 TWS 操作接口 —— 提供左右耳 / 电仓独立电量与充电状态、ADV 广播订阅、
     * Voice Mode 等高级 API。
     *
     * 实现说明：`RCSPController` 通过多层继承（PCSlaveImpl → SPDIFImpl →
     * SoundCardImpl → TwsOpImpl）实现了 [ITwsOp]，强转拿到接口即可。SDK 没暴露
     * 显式 getter，但 `getInstance()` 在 [initialize] 之后保证非 null。
     *
     * 调用方需要做空检查 / `getADVInfo` 返回 null 兜底——单耳设备 / 旧固件可能
     * 不响应 ADV 协议，此时回退到 [DeviceInfoFeature.snapshot] 的 `battery` 字段。
     */
    val twsOp: ITwsOp
        get() = RCSPController.getInstance() as ITwsOp

    private lateinit var bluetoothForwarder: BluetoothEventForwarder
    private lateinit var deviceInfoForwarder: DeviceInfoEventForwarder
    private lateinit var mediaForwarder: MediaEventForwarder
    private lateinit var customForwarder: CustomEventForwarder

    lateinit var scanFeature: ScanFeature
        private set
    lateinit var connectFeature: ConnectFeature
        private set
    lateinit var deviceInfoFeature: DeviceInfoFeature
        private set
    lateinit var customCmdFeature: CustomCmdFeature
        private set
    lateinit var translationFeature: TranslationFeature
        private set
    lateinit var speechFeature: SpeechFeature
        private set
    lateinit var otaFeature: OtaFeature
        private set
    lateinit var deviceRecordFeature: DeviceRecordFeature
        private set

    /** 默认翻译音频桥（EventChannel 透传到 Dart）；宿主 native 想完全自管时可调
     *  [TranslationFeature.setBridge] 替换。
     *
     *  暴露 getter 供 native 编排器（如 [JieliCallTranslationPort]）在 enter/exit
     *  时拿到原始引用做"装上自己的 capture bridge / 退出后还原"切换。
     */
    lateinit var defaultBridge: EventChannelAudioBridge
        private set

    fun initialize(
        context: Context,
        multiDevice: Boolean = true,
        skipNoNameDev: Boolean = false,
        enableLog: Boolean = false,
    ) {
        if (initialized) return

        JL_Log.configureLog(context, enableLog, enableLog)

        // 注意：扫描已不走 Jieli SDK（改为 ScanFeature 内的 BluetoothLeScanner），
        // 所以 BluetoothOption 的 bleScanStrategy / scanFilterData 不再设置——
        // 它们仅影响 SDK 自己的 `btManager.scan()` 路径，留默认即可。
        val option = BluetoothOption.createDefaultOption()
        option.setUseMultiDevice(multiDevice)
        option.setSkipNoNameDev(skipNoNameDev)
        // 关闭设备认证：SDK 默认 isUseDeviceAuth=true，会要求设备走 RCSP 授权流程
        // (`DeviceStatusManager.isAuthBtDevice`)，未授权设备会被拒绝 → 表现为
        // 连上后 RCSP init 完成立刻断开。授权需要服务端发签名密钥的整套基础
        // 设施，目前没接，统一关掉。
        option.setUseDeviceAuth(true)
        android.util.Log.d(
            "JieliHome",
            "init multiDev=$multiDevice skipNoName=$skipNoNameDev useAuth=false"
        )
        RCSPController.init(context, option)

        btManager = RCSPController.getInstance().bluetoothManager
            ?: error("RCSPController.bluetoothManager is null after init")

        // 事件转发层
        bluetoothForwarder = BluetoothEventForwarder(btManager, dispatcher).also { it.attach() }
        deviceInfoForwarder = DeviceInfoEventForwarder(btManager, dispatcher).also { it.attach() }
        mediaForwarder = MediaEventForwarder(btManager, dispatcher).also { it.attach() }
        customForwarder = CustomEventForwarder(btManager, dispatcher).also { it.attach() }

        // 业务功能层
        scanFeature = ScanFeature(context.applicationContext, dispatcher)
        connectFeature = ConnectFeature(btManager)
        deviceInfoFeature = DeviceInfoFeature(btManager)
        customCmdFeature = CustomCmdFeature(btManager)
        translationFeature = TranslationFeature(context.applicationContext, btManager, connectFeature)
        speechFeature = SpeechFeature(btManager, connectFeature, dispatcher).also { it.attach() }
        otaFeature = OtaFeature(btManager, connectFeature, dispatcher)
        deviceRecordFeature = DeviceRecordFeature(this)

        // 默认音频桥：EventChannel；injector 把 Dart 推过来的 PCM 路由回当前 ModeHandler
        defaultBridge = EventChannelAudioBridge(dispatcher) { _, streamId, pcm, fmt, isFinal ->
            translationFeature.feedTranslatedAudio(streamId, pcm, fmt, isFinal)
        }
        translationFeature.setBridge(defaultBridge)

        // 内部级联收尾：连接断开 / 来电状态变化时，自动停止当前翻译，避免脏状态
        dispatcher.addNativeListener(internalCleanupListener)

        initialized = true
    }

    /** 监听若干生命周期事件并触发自动收尾 */
    private val internalCleanupListener = object : com.jielihome.jielihome.api.JieliEventListener {
        override fun onEvent(payload: Map<String, Any?>) {
            when (payload["type"] as? String) {
                "connectionState" -> {
                    val state = payload["state"] as? Int ?: return
                    // StateCode.CONNECTION_DISCONNECT == 0
                    if (state == 0) {
                        if (translationFeature.isWorking()) translationFeature.stop()
                        if (deviceRecordFeature.isRecording()) deviceRecordFeature.stop()
                    }
                }
                "phoneCallStatus" -> {
                    // 来电/通话进行中 (status != 0) 且当前不是通话翻译，自动 exit
                    val status = payload["status"] as? Int ?: return
                    if (status == 0) return
                    val mid = translationFeature.currentModeId() ?: return
                    val isCallMode = mid == com.jieli.bluetooth.bean.translation.TranslationMode.MODE_CALL_TRANSLATION ||
                        mid == com.jieli.bluetooth.bean.translation.TranslationMode.MODE_CALL_TRANSLATION_WITH_STEREO
                    if (!isCallMode && translationFeature.isWorking()) {
                        translationFeature.stop()
                    }
                }
            }
        }
    }

    /** 原生事件订阅 */
    fun addEventListener(listener: JieliEventListener) = dispatcher.addNativeListener(listener)
    fun removeEventListener(listener: JieliEventListener) = dispatcher.removeNativeListener(listener)

    /** 替换翻译音频桥（完全 native 直连翻译服务时使用） */
    fun setTranslationBridge(bridge: TranslationAudioBridge) {
        translationFeature.setBridge(bridge)
    }

    /**
     * 通话翻译能力端口（[com.aiagent.device_plugin_interface.DeviceCallTranslationPort]
     * 的杰理实现）。延迟创建；翻译编排器（translate_server native）通过
     * [DeviceSession.invokeFeature("jieli.callTranslationPort")] 或类似入口拿到引用。
     */
    val callTranslationPort: com.jielihome.jielihome.feature.translation.JieliCallTranslationPort by lazy {
        com.jielihome.jielihome.feature.translation.JieliCallTranslationPort(this)
    }

    /**
     * 设备录音端口 —— 原生层直连入口。
     * 收集 [deviceRecordPort.audioFrames] 获取 PCM 帧，调用 [deviceRecordPort.start]/[stop] 控制录音。
     */
    val deviceRecordPort: com.jielihome.jielihome.feature.record.JieliDeviceRecordPort by lazy {
        com.jielihome.jielihome.feature.record.JieliDeviceRecordPort(this)
    }

    /**
     * AI 助理能力端口（[com.aiagent.device_plugin_interface.DeviceAssistantPort]
     * 的杰理实现）。延迟创建；`assistant_server` native 编排器通过
     * [JieliNativeDeviceSession.assistantPort] 拿引用，与 [callTranslationPort] 语义独立。
     *
     * 底层同样依赖 RCSP `MODE_CALL_TRANSLATION`，但接口上已完全隐藏 leg/翻译语义。
     */
    val assistantPort: com.jielihome.jielihome.feature.assistant.JieliAssistantPort by lazy {
        com.jielihome.jielihome.feature.assistant.JieliAssistantPort(this)
    }

    fun shutdown() {
        if (!initialized) return
        runCatching { otaFeature.cancel() }
        runCatching { deviceRecordFeature.stop() }
        runCatching { translationFeature.stop() }
        runCatching { speechFeature.detach() }
        runCatching { bluetoothForwarder.detach() }
        runCatching { deviceInfoForwarder.detach() }
        runCatching { mediaForwarder.detach() }
        runCatching { customForwarder.detach() }
        initialized = false
    }
}
