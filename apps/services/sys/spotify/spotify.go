package spotify

import (
	"context"

	"github.com/zmb3/spotify/v2"
	spotifyauth "github.com/zmb3/spotify/v2/auth"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/clientcredentials"
)

func newSys(options Options) (sys *Spotify, err error) {
	sys = &Spotify{options: options}
	err = sys.Init()
	return
}

type Spotify struct {
	options Options
	config  *clientcredentials.Config
	auth    *spotifyauth.Authenticator
	client  *spotify.Client
}

func (this *Spotify) Init() (err error) {

	// 获取Token（需要先完成OAuth流程）
	// 创建客户端凭证配置
	this.config = &clientcredentials.Config{
		ClientID:     this.options.ClientID,
		ClientSecret: this.options.ClientSecret,
		TokenURL:     spotifyauth.TokenURL, // Spotify的Token端点
	}

	this.auth = spotifyauth.New(
		spotifyauth.WithClientID(this.options.ClientID),
		spotifyauth.WithClientSecret(this.options.ClientSecret),
		spotifyauth.WithRedirectURL(this.options.RedirectURI),
		spotifyauth.WithScopes(spotifyauth.ScopeUserReadPrivate),
	)

	return
}

func (this *Spotify) SearchMusic(ctx context.Context, query string, limit, offset int) (musics []spotify.FullTrack, err error) {
	var (
		token   *oauth2.Token
		results *spotify.SearchResult
	)
	// 获取Token
	token, err = this.config.Token(context.Background())
	if err != nil {
		return
	}
	// 创建客户端
	this.client = spotify.New(this.auth.Client(context.Background(), token))
	results, err = this.client.Search(ctx, query, spotify.SearchTypeTrack, spotify.Limit(limit), spotify.Offset(offset))
	if err != nil {
		return
	}
	musics = results.Tracks.Tracks
	return
}

func (this *Spotify) SearchMusicList(ctx context.Context, query string, limit, offset int) (musics []spotify.SimplePlaylist, err error) {
	var (
		token   *oauth2.Token
		results *spotify.SearchResult
	)
	// 获取Token
	token, err = this.config.Token(context.Background())
	if err != nil {
		return
	}
	// 创建客户端
	this.client = spotify.New(this.auth.Client(context.Background(), token))
	results, err = this.client.Search(ctx, query, spotify.SearchTypePlaylist, spotify.Limit(limit), spotify.Offset(offset))
	if err != nil {
		return
	}
	musics = results.Playlists.Playlists
	return
}
func (this *Spotify) SearchMusicListDetails(ctx context.Context, id spotify.ID, limit, offset int) (musics []spotify.PlaylistItem, err error) {
	var (
		token   *oauth2.Token
		results *spotify.PlaylistItemPage
	)
	// 获取Token
	token, err = this.config.Token(context.Background())
	if err != nil {
		return
	}
	// 创建客户端
	this.client = spotify.New(this.auth.Client(context.Background(), token))
	results, err = this.client.GetPlaylistItems(ctx, id, spotify.Limit(limit), spotify.Offset(offset))
	if err != nil {
		return
	}
	musics = results.Items
	return
}
