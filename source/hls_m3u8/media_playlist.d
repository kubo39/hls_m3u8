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
private import std.conv : ConvException, to;
private import std.format : format;
private import std.string : startsWith, strip;
private import std.typecons : Nullable, nullable;

private import hls_m3u8.parse_utils;

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

    /// The discontinuity sequence number of the first media segment (EXT-X-DISCONTINUITY-SEQUENCE).
    /// See [RFC 8216 §4.3.3.3](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.3.3).
    uint discontinuitySequence;

    /// Indicates that no more media segments will be added to the playlist (EXT-X-ENDLIST).
    /// See [RFC 8216 §4.3.3.4](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.3.4).
    bool hasEndList;

    /// The mutability type of the playlist (EXT-X-PLAYLIST-TYPE).
    /// See [RFC 8216 §4.3.3.5](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.3.5).
    Nullable!PlaylistType playlistType;

    /// Indicates that each media segment describes a single I-frame (EXT-X-I-FRAMES-ONLY).
    /// See [RFC 8216 §4.3.3.6](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.3.6).
    bool hasIFramesOnly;

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
        uint ver = 3;
        if (hasIFramesOnly)
            ver = 4; // v4: EXT-X-I-FRAMES-ONLY
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
    string toString()
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
        if (discontinuitySequence != 0)
            buf ~= format!"#EXT-X-DISCONTINUITY-SEQUENCE:%d\n"(discontinuitySequence);

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
        if (hasIFramesOnly)
            buf ~= "#EXT-X-I-FRAMES-ONLY\n";

        buf ~= "\n";

        foreach (seg; segments)
        {
            buf ~= seg.toString();
        }

        if (hasEndList)
            buf ~= "#EXT-X-ENDLIST\n";

        return buf[];
    }

    /**
     * Parse an m3u8 string into a MediaPlaylist.
     */
    static MediaPlaylist fromString(string input)
    {
        import std.algorithm : splitter;
        import std.datetime.systime : SysTime;

        MediaPlaylist result;
        bool hasHeader = false;
        bool hasTargetDuration = false;

        // per-segment accumulator
        Nullable!Duration pendingDuration;
        Nullable!ByteRange pendingByteRange;
        Nullable!EncryptionKey pendingKey;
        Nullable!MediaInitializationSection pendingMap;
        Nullable!SysTime pendingProgramDateTime;
        bool pendingDiscontinuity;

        foreach (rawLine; input.splitter('\n'))
        {
            auto line = rawLine.strip;
            if (line.length >= 1 && line[$ - 1] == '\r')
                line = line[0 .. $ - 1];
            if (line.length == 0)
                continue;

            if (!hasHeader)
            {
                if (line != "#EXTM3U")
                    throw new M3U8ParseException("missing #EXTM3U header");
                hasHeader = true;
                continue;
            }

            if (line.startsWith("#EXTINF:"))
            {
                pendingDuration = parseExtinfDuration(line[8 .. $]).nullable;
            }
            else if (line.startsWith("#EXT-X-TARGETDURATION:"))
            {
                try
                    result.targetDuration = dur!"seconds"(line[22 .. $].to!uint);
                catch (ConvException e)
                    throw new M3U8ParseException("invalid EXT-X-TARGETDURATION");
                hasTargetDuration = true;
            }
            else if (line.startsWith("#EXT-X-MEDIA-SEQUENCE:"))
            {
                try
                    result.mediaSequence = line[22 .. $].to!uint;
                catch (ConvException e)
                    throw new M3U8ParseException("invalid EXT-X-MEDIA-SEQUENCE");
            }
            else if (line.startsWith("#EXT-X-DISCONTINUITY-SEQUENCE:"))
            {
                try
                    result.discontinuitySequence = line[30 .. $].to!uint;
                catch (ConvException e)
                    throw new M3U8ParseException("invalid EXT-X-DISCONTINUITY-SEQUENCE");
            }
            else if (line == "#EXT-X-ENDLIST")
            {
                result.hasEndList = true;
            }
            else if (line.startsWith("#EXT-X-PLAYLIST-TYPE:"))
            {
                string val = line[21 .. $];
                if (val == "EVENT")
                    result.playlistType = PlaylistType.event.nullable;
                else if (val == "VOD")
                    result.playlistType = PlaylistType.vod.nullable;
                else
                    throw new M3U8ParseException("invalid EXT-X-PLAYLIST-TYPE: " ~ val);
            }
            else if (line == "#EXT-X-I-FRAMES-ONLY")
            {
                result.hasIFramesOnly = true;
            }
            else if (line == "#EXT-X-DISCONTINUITY")
            {
                pendingDiscontinuity = true;
            }
            else if (line.startsWith("#EXT-X-BYTERANGE:"))
            {
                pendingByteRange = parseByteRange(line[17 .. $]).nullable;
            }
            else if (line.startsWith("#EXT-X-KEY:"))
            {
                auto attrs = parseAttributeList(line[11 .. $]);
                auto method = "METHOD" in attrs;
                if (method is null)
                    throw new M3U8ParseException("EXT-X-KEY: missing METHOD");
                EncryptionKey k;
                if (*method == "NONE")
                    k.method = EncryptionMethod.none;
                else if (*method == "AES-128")
                    k.method = EncryptionMethod.aes128;
                else if (*method == "SAMPLE-AES")
                    k.method = EncryptionMethod.sampleAes;
                else
                    throw new M3U8ParseException("EXT-X-KEY: unknown METHOD: " ~ *method);
                if (auto uri = "URI" in attrs)
                    k.uri = (*uri).nullable;
                if (auto iv = "IV" in attrs)
                    k.iv = parseHexIV(*iv).nullable;
                pendingKey = k.nullable;
            }
            else if (line.startsWith("#EXT-X-MAP:"))
            {
                auto attrs = parseAttributeList(line[11 .. $]);
                auto uri = "URI" in attrs;
                if (uri is null)
                    throw new M3U8ParseException("EXT-X-MAP: missing URI");
                MediaInitializationSection m;
                m.uri = *uri;
                if (auto br = "BYTERANGE" in attrs)
                    m.byteRange = parseByteRange(*br).nullable;
                pendingMap = m.nullable;
            }
            else if (line.startsWith("#EXT-X-PROGRAM-DATE-TIME:"))
            {
                try
                    pendingProgramDateTime = SysTime.fromISOExtString(line[25 .. $]).nullable;
                catch (Exception e)
                    throw new M3U8ParseException("invalid EXT-X-PROGRAM-DATE-TIME: " ~ line[25 .. $]);
            }
            else if (line.startsWith("#"))
            {
                // ignore unknown tags and comments (RFC 8216 §6.3.1)
            }
            else
            {
                // URI line
                if (pendingDuration.isNull)
                    throw new M3U8ParseException("URI without preceding #EXTINF: " ~ line);

                MediaSegment seg;
                seg.uri = line;
                seg.duration = pendingDuration.get;
                seg.byteRange = pendingByteRange;
                seg.hasDiscontinuity = pendingDiscontinuity;
                seg.key = pendingKey;
                seg.map = pendingMap;
                seg.programDateTime = pendingProgramDateTime;
                result.segments ~= seg;

                pendingDuration.nullify();
                pendingByteRange.nullify();
                pendingKey.nullify();
                pendingMap.nullify();
                pendingProgramDateTime.nullify();
                pendingDiscontinuity = false;
            }
        }

        if (!hasHeader)
            throw new M3U8ParseException("missing #EXTM3U header");
        if (!hasTargetDuration)
            throw new M3U8ParseException("missing #EXT-X-TARGETDURATION");
        if (!pendingDuration.isNull)
            throw new M3U8ParseException("trailing #EXTINF without URI");

        return result;
    }
}

///
unittest
{
    import core.time : seconds;

    auto playlist = MediaPlaylist(targetDuration: 5.seconds);
    playlist.addSegment(MediaSegment("segment001.ts", 3.seconds));
    playlist.addSegment(MediaSegment("segment002.ts", 4.seconds));

    assert(playlist.toString() ==
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

    assert(playlist.toString() ==
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

    assert(playlist.toString() ==
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

    assert(playlist.toString() ==
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

    assert(playlist.toString() ==
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
    assert(playlist.toString() ==
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
    assert(playlist.toString() ==
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

///
unittest
{
    import core.time : seconds;
    import std.typecons : nullable;

    ubyte[16] iv = 0;
    iv[15] = 1;
    auto encKey = EncryptionKey(
        method: EncryptionMethod.aes128,
        uri: "https://example.com/key.bin".nullable,
        iv: iv.nullable,
    ).nullable;

    auto playlist = MediaPlaylist(targetDuration: 5.seconds, hasEndList: true);
    playlist.addSegment(MediaSegment(
        "segment001.ts", 5.seconds,
        key: encKey,
    ));
    playlist.addSegment(MediaSegment("segment002.ts", 5.seconds));

    assert(playlist.requiredVersion() == 3);
    assert(playlist.toString() ==
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:3\n"
        ~ "#EXT-X-TARGETDURATION:5\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "\n"
        ~ "#EXT-X-KEY:METHOD=AES-128,URI=\"https://example.com/key.bin\",IV=0x00000000000000000000000000000001\n"
        ~ "#EXTINF:5.000,\n"
        ~ "segment001.ts\n"
        ~ "#EXTINF:5.000,\n"
        ~ "segment002.ts\n"
        ~ "#EXT-X-ENDLIST\n"
    );
}

///
unittest
{
    import core.time : seconds;

    auto playlist = MediaPlaylist(
        targetDuration: 5.seconds,
        discontinuitySequence: 3,
        hasEndList: true,
    );
    playlist.addSegment(MediaSegment("segment001.ts", 5.seconds));
    playlist.addSegment(MediaSegment("segment002.ts", 5.seconds, hasDiscontinuity: true));

    assert(playlist.toString() ==
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:3\n"
        ~ "#EXT-X-TARGETDURATION:5\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "#EXT-X-DISCONTINUITY-SEQUENCE:3\n"
        ~ "\n"
        ~ "#EXTINF:5.000,\n"
        ~ "segment001.ts\n"
        ~ "#EXT-X-DISCONTINUITY\n"
        ~ "#EXTINF:5.000,\n"
        ~ "segment002.ts\n"
        ~ "#EXT-X-ENDLIST\n"
    );
}

///
unittest
{
    import core.time : seconds;
    import std.typecons : nullable;

    auto playlist = MediaPlaylist(
        targetDuration: 5.seconds,
        hasEndList: true,
        hasIFramesOnly: true,
    );
    playlist.addSegment(MediaSegment(
        "main.ts", 5.seconds,
        byteRange: ByteRange(length: 10000, offset: 0uL.nullable).nullable,
    ));
    playlist.addSegment(MediaSegment(
        "main.ts", 5.seconds,
        byteRange: ByteRange(length: 12000, offset: 10000uL.nullable).nullable,
    ));

    assert(playlist.requiredVersion() == 4);
    assert(playlist.toString() ==
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:4\n"
        ~ "#EXT-X-TARGETDURATION:5\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "#EXT-X-I-FRAMES-ONLY\n"
        ~ "\n"
        ~ "#EXT-X-BYTERANGE:10000@0\n"
        ~ "#EXTINF:5.000,\n"
        ~ "main.ts\n"
        ~ "#EXT-X-BYTERANGE:12000@10000\n"
        ~ "#EXTINF:5.000,\n"
        ~ "main.ts\n"
        ~ "#EXT-X-ENDLIST\n"
    );
}

// Round-trip parse tests

/// basic round-trip
unittest
{
    string input =
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:3\n"
        ~ "#EXT-X-TARGETDURATION:5\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "\n"
        ~ "#EXTINF:3.000,\n"
        ~ "segment001.ts\n"
        ~ "#EXTINF:4.000,\n"
        ~ "segment002.ts\n";

    auto playlist = MediaPlaylist.fromString(input);
    assert(playlist.toString() == input);
}

/// round-trip with endlist
unittest
{
    string input =
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:3\n"
        ~ "#EXT-X-TARGETDURATION:5\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "\n"
        ~ "#EXTINF:3.000,\n"
        ~ "segment001.ts\n"
        ~ "#EXT-X-ENDLIST\n";

    assert(MediaPlaylist.fromString(input).toString() == input);
}

/// round-trip with playlist type
unittest
{
    string input =
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:3\n"
        ~ "#EXT-X-TARGETDURATION:10\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "#EXT-X-PLAYLIST-TYPE:VOD\n"
        ~ "\n"
        ~ "#EXTINF:5.000,\n"
        ~ "segment001.ts\n"
        ~ "#EXT-X-ENDLIST\n";

    assert(MediaPlaylist.fromString(input).toString() == input);
}

/// round-trip with discontinuity
unittest
{
    string input =
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
        ~ "#EXT-X-ENDLIST\n";

    assert(MediaPlaylist.fromString(input).toString() == input);
}

/// round-trip with program-date-time
unittest
{
    string input =
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
        ~ "#EXT-X-ENDLIST\n";

    assert(MediaPlaylist.fromString(input).toString() == input);
}

/// round-trip with byte range
unittest
{
    string input =
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
        ~ "#EXT-X-ENDLIST\n";

    assert(MediaPlaylist.fromString(input).toString() == input);
}

/// round-trip with EXT-X-MAP
unittest
{
    string input =
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
        ~ "#EXT-X-ENDLIST\n";

    assert(MediaPlaylist.fromString(input).toString() == input);
}

/// round-trip with EXT-X-KEY
unittest
{
    string input =
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:3\n"
        ~ "#EXT-X-TARGETDURATION:5\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "\n"
        ~ "#EXT-X-KEY:METHOD=AES-128,URI=\"https://example.com/key.bin\",IV=0x00000000000000000000000000000001\n"
        ~ "#EXTINF:5.000,\n"
        ~ "segment001.ts\n"
        ~ "#EXTINF:5.000,\n"
        ~ "segment002.ts\n"
        ~ "#EXT-X-ENDLIST\n";

    assert(MediaPlaylist.fromString(input).toString() == input);
}

/// round-trip with discontinuity sequence
unittest
{
    string input =
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:3\n"
        ~ "#EXT-X-TARGETDURATION:5\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "#EXT-X-DISCONTINUITY-SEQUENCE:3\n"
        ~ "\n"
        ~ "#EXTINF:5.000,\n"
        ~ "segment001.ts\n"
        ~ "#EXT-X-DISCONTINUITY\n"
        ~ "#EXTINF:5.000,\n"
        ~ "segment002.ts\n"
        ~ "#EXT-X-ENDLIST\n";

    assert(MediaPlaylist.fromString(input).toString() == input);
}

/// round-trip with I-frames-only
unittest
{
    string input =
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:4\n"
        ~ "#EXT-X-TARGETDURATION:5\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "#EXT-X-I-FRAMES-ONLY\n"
        ~ "\n"
        ~ "#EXT-X-BYTERANGE:10000@0\n"
        ~ "#EXTINF:5.000,\n"
        ~ "main.ts\n"
        ~ "#EXT-X-BYTERANGE:12000@10000\n"
        ~ "#EXTINF:5.000,\n"
        ~ "main.ts\n"
        ~ "#EXT-X-ENDLIST\n";

    assert(MediaPlaylist.fromString(input).toString() == input);
}

/// unknown tags are ignored
unittest
{
    string input =
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:3\n"
        ~ "#EXT-X-TARGETDURATION:5\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "#EXT-X-UNKNOWN-TAG:some-value\n"
        ~ "\n"
        ~ "#EXTINF:3.000,\n"
        ~ "segment001.ts\n";

    auto playlist = MediaPlaylist.fromString(input);
    assert(playlist.segments.length == 1);
}

/// integer EXTINF (v1/v2 compat)
unittest
{
    string input =
        "#EXTM3U\n"
        ~ "#EXT-X-TARGETDURATION:10\n"
        ~ "#EXT-X-MEDIA-SEQUENCE:0\n"
        ~ "\n"
        ~ "#EXTINF:10,\n"
        ~ "segment001.ts\n";

    auto playlist = MediaPlaylist.fromString(input);
    assert(playlist.segments.length == 1);
    assert(playlist.segments[0].uri == "segment001.ts");
}
