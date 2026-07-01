package spotify_test

import (
	"context"
	"fmt"
	"log"
	"os"
	"testing"
	lgspotify "yunyan/sys/spotify"

	"github.com/zmb3/spotify/v2"
	spotifyauth "github.com/zmb3/spotify/v2/auth"
	"golang.org/x/oauth2/clientcredentials"
)

var (
	clientID     = os.Getenv("SPOTIFY_CLIENT_ID")
	clientSecret = os.Getenv("SPOTIFY_CLIENT_SECRET")
)

const redirectURI = "http://localhost:8080/callback"

var (
	ctx  = context.Background()
	auth = spotifyauth.New(
		spotifyauth.WithClientID(clientID),
		spotifyauth.WithClientSecret(clientSecret),
		spotifyauth.WithRedirectURL(redirectURI),
		spotifyauth.WithScopes(spotifyauth.ScopeUserReadPrivate),
	)
)

func getTrackLinkBySearch(client *spotify.Client, query string) {
	results, err := client.Search(ctx, query, spotify.SearchTypeTrack)
	if err != nil {
		log.Fatal("搜索失败:", err)
	}

	if len(results.Tracks.Tracks) == 0 {
		fmt.Println("未找到相关曲目")
		return
	}

	for i, track := range results.Tracks.Tracks {
		fmt.Printf("\n曲目 %d:\n", i+1)
		printTrackInfo(track)
	}
}

func getTrackLinkByID(client *spotify.Client, trackID string) {
	track, err := client.GetTrack(ctx, spotify.ID(trackID))
	if err != nil {
		log.Fatal("获取曲目失败:", err)
	}

	fmt.Println("\n通过ID获取结果:")
	printTrackInfo(*track)
}

func printTrackInfo(track spotify.FullTrack) {
	fmt.Println("曲目名称:", track.Name)
	fmt.Println("艺术家:", track.Artists[0].Name)
	fmt.Println("专辑:", track.Album.Name)
	fmt.Println("标准链接:", track.ExternalURLs["spotify"])
	fmt.Println("直接播放链接:", track.URI) // 格式: spotify:track:3AJwUDP919kvQ9QcozQPxg
	fmt.Println("网页播放链接:", track.ExternalURLs["spotify"])
	fmt.Println("专辑封面:", track.Album.Images[0].URL)
}
func Test_sys(t *testing.T) {
	if clientID == "" || clientSecret == "" {
		t.Skip("SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET not set, skip")
	}
	// 创建客户端凭证配置
	config := &clientcredentials.Config{
		ClientID:     clientID,
		ClientSecret: clientSecret,
		TokenURL:     spotifyauth.TokenURL, // Spotify的Token端点
	}

	// 获取Token
	token, err := config.Token(context.Background())
	if err != nil {
		log.Fatal("获取Token失败:", err)
	}
	// accessToken := token.AccessToken
	// 创建客户端
	client := spotify.New(auth.Client(ctx, token))

	// 示例1：通过搜索获取链接
	getTrackLinkBySearch(client, "Yellow Coldplay")

	// 示例2：直接通过ID获取
	getTrackLinkByID(client, "3AJwUDP919kvQ9QcozQPxg")
}

func Test_sysspotify(t *testing.T) {
	if clientID == "" || clientSecret == "" {
		t.Skip("SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET not set, skip")
	}
	if sys, err := lgspotify.NewSys(
		lgspotify.SetClientID(clientID),
		lgspotify.SetClientSecret(clientSecret),
		lgspotify.SetRedirectURI(redirectURI),
	); err == nil {
		data, err := sys.SearchMusicList(context.Background(), "热门", 5, 0)
		fmt.Println(data, err)
	}
}
