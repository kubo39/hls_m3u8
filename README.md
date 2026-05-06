# hls_m3u8

A [HLS][rfc8216] m3u8 playlist library for D.
Currently supports playlist generation only (parsing is not yet implemented).

## Usage

### Generate a VOD playlist

```d
import core.time : seconds;
import hls_m3u8;

auto playlist = MediaPlaylist(targetDuration: 5.seconds, hasEndList: true);
playlist.addSegment(MediaSegment("segment001.ts", 3.seconds));
playlist.addSegment(MediaSegment("segment002.ts", 4.seconds));

string m3u8 = playlist.serialize();
```

Output:

```
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:5
#EXT-X-MEDIA-SEQUENCE:0

#EXTINF:3.000,
segment001.ts
#EXTINF:4.000,
segment002.ts
#EXT-X-ENDLIST
```

## License

[BSL-1.0](LICENSE_1_0.txt)

[rfc8216]: https://datatracker.ietf.org/doc/html/rfc8216
