/**
 * The media segment of [HLS](https://datatracker.ietf.org/doc/html/rfc8216).
 *
 * Authors: Hiroki Noda
 * Copyright: Copyright © 2026 Hiroki Noda
 * License: BSL-1.0
*/
module hls_m3u8.media_segment;

private import core.time : Duration;

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
}
