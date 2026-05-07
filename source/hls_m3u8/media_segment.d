/**
 * The media segment of [HLS](https://datatracker.ietf.org/doc/html/rfc8216).
 *
 * Authors: Hiroki Noda
 * Copyright: Copyright © 2026 Hiroki Noda
 * License: BSL-1.0
*/
module hls_m3u8.media_segment;

private import core.time : Duration;

private import std.array : appender;
private import std.datetime.systime : SysTime;
private import std.format : format;
private import std.typecons : Nullable;

@safe:

/// A sub-range of a resource (EXT-X-BYTERANGE).
/// See [RFC 8216 §4.3.2.2](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.2).
struct ByteRange
{
    /// The length of the sub-range in bytes.
    ulong length;

    /// The offset from the beginning of the resource. If not specified,
    /// the sub-range begins at the byte following the end of the previous sub-range.
    Nullable!ulong offset;
}

/**
 * A media segment.
 */
struct MediaSegment
{
    /// A URI to the media segment resource.
    /// See [RFC 8216 §4.3.2.1](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.1).
    string uri;

    /// The duration of the media segment specified by the EXTINF tag.
    /// See [RFC 8216 §4.3.2.1](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.1).
    Duration duration;

    /// Indicates a discontinuity between this segment and the previous one (EXT-X-DISCONTINUITY).
    /// See [RFC 8216 §4.3.2.3](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.3).
    bool hasDiscontinuity;

    /// The absolute date and time of the first sample of the segment (EXT-X-PROGRAM-DATE-TIME).
    /// See [RFC 8216 §4.3.2.6](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.6).
    Nullable!SysTime programDateTime;

    /// A sub-range of the resource identified by the URI (EXT-X-BYTERANGE).
    /// See [RFC 8216 §4.3.2.2](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.2).
    Nullable!ByteRange byteRange;

    /**
     * Returns the minimum HLS version required by this segment's tags.
     */
    uint requiredVersion()
    {
        uint ver = 3;
        if (!byteRange.isNull)
            ver = ver > 4 ? ver : 4; // v4: EXT-X-BYTERANGE
        return ver;
    }

    /**
     * Serialize the media segment.
     */
    string serialize()
    {
        auto buf = appender!string;

        if (hasDiscontinuity)
            buf ~= "#EXT-X-DISCONTINUITY\n";
        if (!programDateTime.isNull)
            buf ~= format!"#EXT-X-PROGRAM-DATE-TIME:%s\n"(programDateTime.get.toISOExtString());
        if (!byteRange.isNull)
        {
            auto br = byteRange.get;
            if (br.offset.isNull)
                buf ~= format!"#EXT-X-BYTERANGE:%d\n"(br.length);
            else
                buf ~= format!"#EXT-X-BYTERANGE:%d@%d\n"(br.length, br.offset.get);
        }
        buf ~= format!"#EXTINF:%.3f,\n"(duration.total!"msecs" / 1000);
        buf ~= uri ~ "\n";

        return buf[];
    }
}
