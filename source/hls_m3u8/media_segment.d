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

/// The encryption method for media segments (EXT-X-KEY).
/// See [RFC 8216 §4.3.2.4](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.4).
enum EncryptionMethod
{
    /// No encryption.
    none,
    /// AES-128 encryption with PKCS7 padding.
    aes128,
    /// SAMPLE-AES encryption.
    sampleAes,
}

/// Specifies how a media segment is encrypted (EXT-X-KEY).
/// See [RFC 8216 §4.3.2.4](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.4).
struct EncryptionKey
{
    /// The encryption method.
    EncryptionMethod method;

    /// The URI for obtaining the key. Required unless method is none.
    Nullable!string uri;

    /// The initialization vector as a 128-bit hexadecimal number.
    Nullable!(ubyte[16]) iv;
}

/// Specifies how to obtain the Media Initialization Section (EXT-X-MAP).
/// See [RFC 8216 §4.3.2.5](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.5).
struct MediaInitializationSection
{
    /// The URI of the resource containing the initialization section.
    string uri;

    /// An optional byte range within the resource.
    Nullable!ByteRange byteRange;
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
    /// Serialized via SysTime.toISOExtString(). RFC 8216 SHOULD recommends millisecond-precision
    /// fractional seconds, but we use SysTime's default output which omits zero fractional parts
    /// and may include sub-millisecond digits. This is valid ISO 8601 and not a MUST requirement.
    /// See [RFC 8216 §4.3.2.6](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.6).
    Nullable!SysTime programDateTime;

    /// A sub-range of the resource identified by the URI (EXT-X-BYTERANGE).
    /// See [RFC 8216 §4.3.2.2](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.2).
    Nullable!ByteRange byteRange;

    /// The Media Initialization Section for this segment (EXT-X-MAP).
    /// See [RFC 8216 §4.3.2.5](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.5).
    Nullable!MediaInitializationSection map;

    /// The encryption key for this segment (EXT-X-KEY).
    /// See [RFC 8216 §4.3.2.4](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.4).
    Nullable!EncryptionKey key;

    /**
     * Returns the minimum HLS version required by this segment's tags.
     */
    uint requiredVersion()
    {
        uint ver = 3;
        if (!byteRange.isNull)
            ver = ver > 4 ? ver : 4; // v4: EXT-X-BYTERANGE
        if (!key.isNull && key.get.method == EncryptionMethod.sampleAes)
            ver = ver > 5 ? ver : 5; // v5: SAMPLE-AES
        if (!map.isNull)
            ver = ver > 6 ? ver : 6; // v6: EXT-X-MAP in Media Playlist
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
        if (!key.isNull)
        {
            auto k = key.get;
            final switch (k.method)
            {
                case EncryptionMethod.none:
                    buf ~= "#EXT-X-KEY:METHOD=NONE\n";
                    break;
                case EncryptionMethod.aes128:
                case EncryptionMethod.sampleAes:
                    if (k.uri.isNull)
                        throw new Exception("EXT-X-KEY: URI is required when METHOD is not NONE");
                    string method = k.method == EncryptionMethod.aes128 ? "AES-128" : "SAMPLE-AES";
                    buf ~= format!"#EXT-X-KEY:METHOD=%s,URI=\"%s\""(method, k.uri.get);
                    if (!k.iv.isNull)
                    {
                        buf ~= ",IV=0x";
                        foreach (b; k.iv.get)
                            buf ~= format!"%02X"(b);
                    }
                    buf ~= "\n";
                    break;
            }
        }
        if (!map.isNull)
        {
            auto m = map.get;
            if (m.byteRange.isNull)
                buf ~= format!"#EXT-X-MAP:URI=\"%s\"\n"(m.uri);
            else
            {
                auto br = m.byteRange.get;
                if (br.offset.isNull)
                    buf ~= format!"#EXT-X-MAP:URI=\"%s\",BYTERANGE=\"%d\"\n"(m.uri, br.length);
                else
                    buf ~= format!"#EXT-X-MAP:URI=\"%s\",BYTERANGE=\"%d@%d\"\n"(m.uri, br.length, br.offset.get);
            }
        }
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
