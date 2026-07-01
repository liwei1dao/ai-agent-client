package spotify

import (
	"context"

	"github.com/zmb3/spotify/v2"
)

type (
	ISys interface {
		SearchMusic(ctx context.Context, query string, limit, offset int) (musics []spotify.FullTrack, err error)
		SearchMusicList(ctx context.Context, query string, limit, offset int) (musics []spotify.SimplePlaylist, err error)
		SearchMusicListDetails(ctx context.Context, id spotify.ID, limit, offset int) (musics []spotify.PlaylistItem, err error)
	}
)

var (
	defsys ISys
)

func OnInit(config map[string]interface{}, option ...Option) (err error) {
	defsys, err = newSys(newOptions(config, option...))
	return
}

func NewSys(option ...Option) (sys ISys, err error) {
	sys, err = newSys(newOptionsByOption(option...))
	return
}

func SearchMusic(ctx context.Context, query string, limit, offset int) (musics []spotify.FullTrack, err error) {
	return defsys.SearchMusic(ctx, query, limit, offset)
}

func SearchMusicList(ctx context.Context, query string, limit, offset int) (musics []spotify.SimplePlaylist, err error) {
	return defsys.SearchMusicList(ctx, query, limit, offset)
}

func SearchMusicListDetails(ctx context.Context, id spotify.ID, limit, offset int) (musics []spotify.PlaylistItem, err error) {
	return defsys.SearchMusicListDetails(ctx, id, limit, offset)
}
