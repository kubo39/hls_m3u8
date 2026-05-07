/**
 * The media playlist of [HLS](https://datatracker.ietf.org/doc/html/rfc8216).
 *
 * Authors: Hiroki Noda
 * Copyright: Copyright © 2026 Hiroki Noda
 * License: BSL-1.0
*/
module hls_m3u8.media_playlist;

private import core.time : Duration, dur;

private import std.array : appender;
private import std.format : format;
private import std.typecons : Nullable, nullable;

public import hls_m3u8.media_segment;

@safe:

/// Provides mutability information about a Media Playlist (EXT-X-PLAYLIST-TYPE).
/// See [RFC 8216 §4.3.3.5](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.3.5).
enum PlaylistType
{
    /// The playlist may have segments appended but never removed.
    event,
    /// The playlist will not change.
    vod,
}

/**
 * A Media Playlist.
 */
struct MediaPlaylist
{
    /// The maximum duration of any media segment in the playlist (EXT-X-TARGETDURATION).
    /// See [RFC 8216 §4.3.3.1](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.3.1).
    Duration targetDuration;

    /// The media sequence number of the first media segment in the playlist (EXT-X-MEDIA-SEQUENCE).
    /// See [RFC 8216 §4.3.3.2](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.3.2).
    uint mediaSequence;

    /// The mutability type of the playlist (EXT-X-PLAYLIST-TYPE).
    /// See [RFC 8216 §4.3.3.5](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.3.5).
    Nullable!PlaylistType playlistType;

    /// Indicates that no more media segments will be added to the playlist (EXT-X-ENDLIST).
    /// See [RFC 8216 §4.3.3.4](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.3.4).
    bool hasEndList;

    /// The list of media segments in the playlist.
    MediaSegment[] segments;

    /**
     * Add a media segment.
     */
    void addSegment(MediaSegment segment)
    {
        segments ~= segment;
    }

    /**
     * Returns the required HLS version based on the tags used.
     */
    uint requiredVersion()
    {
        // v3: EXTINF with decimal duration (always used)
        uint ver = 3;
        foreach (seg; segments)
        {
            auto segVer = seg.requiredVersion();
            if (segVer > ver)
                ver = segVer;
        }
        return ver;
    }

    /**
     * Serialize the playlist and its media segments.
     */
    string serialize()
    {
        Duration maxDur = targetDuration;
        foreach (seg; segments)
        {
            if (seg.duration > maxDur)
                maxDur = seg.duration;
        }

        auto buf = appender!string;
        buf ~= "#EXTM3U\n";
        buf ~= format!"#EXT-X-VERSION:%d\n"(requiredVersion());
        buf ~= format!"#EXT-X-TARGETDURATION:%d\n"((maxDur.total!"msecs" + 999) / 1000);
        buf ~= format!"#EXT-X-MEDIA-SEQUENCE:%d\n"(mediaSequence);

        if (!playlistType.isNull)
        {
            final switch (playlistType.get)
            {
                case PlaylistType.event:
                    buf ~= "#EXT-X-PLAYLIST-TYPE:EVENT\n";
                    break;
                case PlaylistType.vod:
                    buf ~= "#EXT-X-PLAYLIST-TYPE:VOD\n";
                    break;
            }
        }

        buf ~= "\n";

        foreach (seg; segments)
        {
            buf ~= seg.serialize();
        }

        if (hasEndList)
            buf ~= "#EXT-X-ENDLIST\n";

        return buf[];
    }
}

///
unittest
{
    import core.time : seconds;

    auto playlist = MediaPlaylist(targetDuration: 5.seconds);
    playlist.addSegment(MediaSegment("segment001.ts", 3.seconds));
    playlist.addSegment(MediaSegment("segment002.ts", 4.seconds));

    assert(playlist.serialize() ==
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:3\n"
        ~ "#EXT-X-TARGETDURATION:5\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "\n"
        ~ "#EXTINF:3.000,\n"
        ~ "segment001.ts\n"
        ~ "#EXTINF:4.000,\n"
        ~ "segment002.ts\n"
    );
}

///
unittest
{
    import core.time : seconds;

    auto playlist = MediaPlaylist(targetDuration: 5.seconds, hasEndList: true);
    playlist.addSegment(MediaSegment("segment001.ts", 3.seconds));

    assert(playlist.serialize() ==
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:3\n"
        ~ "#EXT-X-TARGETDURATION:5\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "\n"
        ~ "#EXTINF:3.000,\n"
        ~ "segment001.ts\n"
        ~ "#EXT-X-ENDLIST\n"
    );
}

///
unittest
{
    import core.time : seconds;

    auto playlist = MediaPlaylist(
        targetDuration: 10.seconds,
        playlistType: PlaylistType.vod.nullable,
        hasEndList: true,
    );
    playlist.addSegment(MediaSegment("segment001.ts", 5.seconds));

    assert(playlist.serialize() ==
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:3\n"
        ~ "#EXT-X-TARGETDURATION:10\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "#EXT-X-PLAYLIST-TYPE:VOD\n"
        ~ "\n"
        ~ "#EXTINF:5.000,\n"
        ~ "segment001.ts\n"
        ~ "#EXT-X-ENDLIST\n"
    );
}

///
unittest
{
    import core.time : seconds;

    auto playlist = MediaPlaylist(targetDuration: 5.seconds, hasEndList: true);
    playlist.addSegment(MediaSegment("segment001.ts", 3.seconds));
    playlist.addSegment(MediaSegment("segment002.ts", 4.seconds, hasDiscontinuity: true));

    assert(playlist.serialize() ==
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:3\n"
        ~ "#EXT-X-TARGETDURATION:5\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "\n"
        ~ "#EXTINF:3.000,\n"
        ~ "segment001.ts\n"
        ~ "#EXT-X-DISCONTINUITY\n"
        ~ "#EXTINF:4.000,\n"
        ~ "segment002.ts\n"
        ~ "#EXT-X-ENDLIST\n"
    );
}

///
unittest
{
    import core.time : seconds;
    import std.datetime : DateTime, UTC;
    import std.datetime.systime : SysTime;
    import std.typecons : nullable;

    auto playlist = MediaPlaylist(targetDuration: 5.seconds, hasEndList: true);
    playlist.addSegment(MediaSegment(
        "segment001.ts", 3.seconds,
        programDateTime: SysTime(DateTime(2026, 5, 8, 12, 0, 0), UTC()).nullable,
    ));
    playlist.addSegment(MediaSegment("segment002.ts", 4.seconds));

    assert(playlist.serialize() ==
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:3\n"
        ~ "#EXT-X-TARGETDURATION:5\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "\n"
        ~ "#EXT-X-PROGRAM-DATE-TIME:2026-05-08T12:00:00Z\n"
        ~ "#EXTINF:3.000,\n"
        ~ "segment001.ts\n"
        ~ "#EXTINF:4.000,\n"
        ~ "segment002.ts\n"
        ~ "#EXT-X-ENDLIST\n"
    );
}

///
unittest
{
    import core.time : seconds;
    import std.typecons : nullable;

    auto playlist = MediaPlaylist(targetDuration: 10.seconds, hasEndList: true);
    playlist.addSegment(MediaSegment(
        "main.ts", 5.seconds,
        byteRange: ByteRange(length: 10000, offset: 0uL.nullable).nullable,
    ));
    playlist.addSegment(MediaSegment(
        "main.ts", 5.seconds,
        byteRange: ByteRange(length: 15000, offset: 10000uL.nullable).nullable,
    ));

    assert(playlist.requiredVersion() == 4);
    assert(playlist.serialize() ==
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:4\n"
        ~ "#EXT-X-TARGETDURATION:10\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "\n"
        ~ "#EXT-X-BYTERANGE:10000@0\n"
        ~ "#EXTINF:5.000,\n"
        ~ "main.ts\n"
        ~ "#EXT-X-BYTERANGE:15000@10000\n"
        ~ "#EXTINF:5.000,\n"
        ~ "main.ts\n"
        ~ "#EXT-X-ENDLIST\n"
    );
}

///
unittest
{
    import core.time : seconds;
    import std.typecons : nullable;

    auto initSection = MediaInitializationSection(uri: "init.mp4").nullable;
    auto playlist = MediaPlaylist(targetDuration: 6.seconds, hasEndList: true);
    playlist.addSegment(MediaSegment(
        "segment001.m4s", 6.seconds,
        map: initSection,
    ));
    playlist.addSegment(MediaSegment(
        "segment002.m4s", 6.seconds,
    ));

    assert(playlist.requiredVersion() == 6);
    assert(playlist.serialize() ==
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:6\n"
        ~ "#EXT-X-TARGETDURATION:6\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "\n"
        ~ "#EXT-X-MAP:URI=\"init.mp4\"\n"
        ~ "#EXTINF:6.000,\n"
        ~ "segment001.m4s\n"
        ~ "#EXTINF:6.000,\n"
        ~ "segment002.m4s\n"
        ~ "#EXT-X-ENDLIST\n"
    );
}
