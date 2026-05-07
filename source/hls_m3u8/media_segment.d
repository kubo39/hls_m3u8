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
private import std.format : format;

@safe:

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

    /**
     * Serialize the media segment.
     */
    string serialize()
    {
        auto buf = appender!string;

        if (hasDiscontinuity)
            buf ~= "#EXT-X-DISCONTINUITY\n";
        buf ~= format!"#EXTINF:%.3f,\n"(duration.total!"msecs" / 1000);
        buf ~= uri ~ "\n";

        return buf[];
    }
}
