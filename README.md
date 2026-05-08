# hls_m3u8

A [HLS][rfc8216] m3u8 parser/generator for D.

## Usage

### Generate a Media Playlist

```d
import core.time : seconds;
import hls_m3u8;

auto playlist = MediaPlaylist(targetDuration: 5.seconds, hasEndList: true);
playlist.addSegment(MediaSegment("segment001.ts", 3.seconds));
playlist.addSegment(MediaSegment("segment002.ts", 4.seconds));

string m3u8 = playlist.toString();
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

### Parse a Media Playlist

```d
import hls_m3u8;

auto playlist = MediaPlaylist.fromString(m3u8Input);
```

### Generate a Master Playlist

```d
import hls_m3u8;
import std.typecons : nullable;

auto master = MasterPlaylist();
master.addVariant(VariantStream(
    "720p/stream.m3u8",
    bandwidth: 2_560_000,
    codecs: "avc1.4d401e,mp4a.40.2".nullable,
    resolution: Resolution(1280, 720).nullable,
));
master.addVariant(VariantStream(
    "1080p/stream.m3u8",
    bandwidth: 7_680_000,
    codecs: "avc1.4d401e,mp4a.40.2".nullable,
    resolution: Resolution(1920, 1080).nullable,
));

string m3u8 = master.toString();
```

### Parse a Master Playlist

```d
import hls_m3u8;

auto master = MasterPlaylist.fromString(m3u8Input);
```

## License

[BSL-1.0](LICENSE_1_0.txt)

[rfc8216]: https://datatracker.ietf.org/doc/html/rfc8216
