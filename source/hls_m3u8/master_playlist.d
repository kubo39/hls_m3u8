/**
 * The master playlist of [HLS](https://datatracker.ietf.org/doc/html/rfc8216).
 *
 * Authors: Hiroki Noda
 * Copyright: Copyright © 2026 Hiroki Noda
 * License: BSL-1.0
*/
module hls_m3u8.master_playlist;

private import std.array : appender;
private import std.conv : ConvException, to;
private import std.format : format;
private import std.string : startsWith, strip;
private import std.typecons : Nullable, nullable;

private import hls_m3u8.parse_utils;

@safe:

/// Display resolution as width x height.
struct Resolution
{
    /// The horizontal pixel count.
    uint width;

    /// The vertical pixel count.
    uint height;
}

/// A variant stream in the Master Playlist (EXT-X-STREAM-INF).
/// See [RFC 8216 §4.3.4.2](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.4.2).
struct VariantStream
{
    /// The URI to the Media Playlist for this variant.
    string uri;

    /// Peak segment bitrate in bits per second (required).
    uint bandwidth;

    /// Average segment bitrate in bits per second.
    Nullable!uint averageBandwidth;

    /// Comma-separated list of codec identifiers per RFC 6381.
    Nullable!string codecs;

    /// Optimal display resolution.
    Nullable!Resolution resolution;

    /// Maximum frame rate, rounded to 3 decimal places.
    Nullable!double frameRate;

    /**
     * Serialize the variant stream.
     */
    string toString()
    {
        auto buf = appender!string;
        buf ~= format!"#EXT-X-STREAM-INF:BANDWIDTH=%d"(bandwidth);
        if (!averageBandwidth.isNull)
            buf ~= format!",AVERAGE-BANDWIDTH=%d"(averageBandwidth.get);
        if (!codecs.isNull)
            buf ~= format!",CODECS=\"%s\""(codecs.get);
        if (!resolution.isNull)
        {
            auto r = resolution.get;
            buf ~= format!",RESOLUTION=%dx%d"(r.width, r.height);
        }
        if (!frameRate.isNull)
            buf ~= format!",FRAME-RATE=%.3f"(frameRate.get);
        buf ~= "\n";
        buf ~= uri ~ "\n";
        return buf[];
    }
}

/**
 * A Master Playlist.
 */
struct MasterPlaylist
{
    /// The list of variant streams in the playlist.
    VariantStream[] variants;

    /**
     * Add a variant stream.
     */
    void addVariant(VariantStream variant)
    {
        variants ~= variant;
    }

    /**
     * Serialize the master playlist.
     */
    string toString()
    {
        auto buf = appender!string;
        buf ~= "#EXTM3U\n";

        foreach (variant; variants)
        {
            buf ~= variant.toString();
        }

        return buf[];
    }

    /**
     * Parse an m3u8 string into a MasterPlaylist.
     */
    static MasterPlaylist fromString(string input)
    {
        import std.algorithm : findSplit, splitter;

        MasterPlaylist result;
        bool hasHeader = false;

        // per-variant accumulator
        bool hasPendingVariant = false;
        uint pendingBandwidth;
        Nullable!uint pendingAvgBandwidth;
        Nullable!string pendingCodecs;
        Nullable!Resolution pendingResolution;
        Nullable!double pendingFrameRate;

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

            if (line.startsWith("#EXT-X-STREAM-INF:"))
            {
                auto attrs = parseAttributeList(line[18 .. $]);
                auto bw = "BANDWIDTH" in attrs;
                if (bw is null)
                    throw new M3U8ParseException("EXT-X-STREAM-INF: missing BANDWIDTH");
                try
                    pendingBandwidth = (*bw).to!uint;
                catch (ConvException e)
                    throw new M3U8ParseException("EXT-X-STREAM-INF: invalid BANDWIDTH");

                if (auto v = "AVERAGE-BANDWIDTH" in attrs)
                {
                    try
                        pendingAvgBandwidth = (*v).to!uint.nullable;
                    catch (ConvException e)
                        throw new M3U8ParseException("EXT-X-STREAM-INF: invalid AVERAGE-BANDWIDTH");
                }
                if (auto v = "CODECS" in attrs)
                    pendingCodecs = (*v).nullable;
                if (auto v = "RESOLUTION" in attrs)
                {
                    auto parts = (*v).findSplit("x");
                    if (parts[1].length == 0)
                        throw new M3U8ParseException("EXT-X-STREAM-INF: invalid RESOLUTION");
                    try
                        pendingResolution = Resolution(parts[0].to!uint, parts[2].to!uint).nullable;
                    catch (ConvException e)
                        throw new M3U8ParseException("EXT-X-STREAM-INF: invalid RESOLUTION");
                }
                if (auto v = "FRAME-RATE" in attrs)
                {
                    try
                        pendingFrameRate = (*v).to!double.nullable;
                    catch (ConvException e)
                        throw new M3U8ParseException("EXT-X-STREAM-INF: invalid FRAME-RATE");
                }
                hasPendingVariant = true;
            }
            else if (line.startsWith("#"))
            {
                // ignore unknown tags and comments
            }
            else
            {
                // URI line
                if (!hasPendingVariant)
                    throw new M3U8ParseException("URI without preceding #EXT-X-STREAM-INF: " ~ line);

                VariantStream variant;
                variant.uri = line;
                variant.bandwidth = pendingBandwidth;
                variant.averageBandwidth = pendingAvgBandwidth;
                variant.codecs = pendingCodecs;
                variant.resolution = pendingResolution;
                variant.frameRate = pendingFrameRate;
                result.variants ~= variant;

                hasPendingVariant = false;
                pendingAvgBandwidth.nullify();
                pendingCodecs.nullify();
                pendingResolution.nullify();
                pendingFrameRate.nullify();
            }
        }

        if (!hasHeader)
            throw new M3U8ParseException("missing #EXTM3U header");
        if (hasPendingVariant)
            throw new M3U8ParseException("trailing #EXT-X-STREAM-INF without URI");

        return result;
    }
}

///
unittest
{
    auto playlist = MasterPlaylist();
    playlist.addVariant(VariantStream("low/index.m3u8", bandwidth: 1_000_000));
    playlist.addVariant(VariantStream("high/index.m3u8", bandwidth: 5_000_000));

    assert(playlist.toString() ==
        "#EXTM3U\n"
        ~ "#EXT-X-STREAM-INF:BANDWIDTH=1000000\n"
        ~ "low/index.m3u8\n"
        ~ "#EXT-X-STREAM-INF:BANDWIDTH=5000000\n"
        ~ "high/index.m3u8\n"
    );
}

///
unittest
{
    import std.typecons : nullable;

    auto playlist = MasterPlaylist();
    playlist.addVariant(VariantStream(
        "720p/stream.m3u8",
        bandwidth: 2_560_000,
        codecs: "avc1.4d401e,mp4a.40.2".nullable,
        resolution: Resolution(1280, 720).nullable,
    ));
    playlist.addVariant(VariantStream(
        "1080p/stream.m3u8",
        bandwidth: 7_680_000,
        codecs: "avc1.4d401e,mp4a.40.2".nullable,
        resolution: Resolution(1920, 1080).nullable,
    ));

    assert(playlist.toString() ==
        "#EXTM3U\n"
        ~ "#EXT-X-STREAM-INF:BANDWIDTH=2560000,CODECS=\"avc1.4d401e,mp4a.40.2\",RESOLUTION=1280x720\n"
        ~ "720p/stream.m3u8\n"
        ~ "#EXT-X-STREAM-INF:BANDWIDTH=7680000,CODECS=\"avc1.4d401e,mp4a.40.2\",RESOLUTION=1920x1080\n"
        ~ "1080p/stream.m3u8\n"
    );
}

///
unittest
{
    import std.typecons : nullable;

    auto playlist = MasterPlaylist();
    playlist.addVariant(VariantStream(
        "video.m3u8",
        bandwidth: 3_000_000,
        averageBandwidth: 2_500_000u.nullable,
        codecs: "avc1.4d401e,mp4a.40.2".nullable,
        resolution: Resolution(1280, 720).nullable,
        frameRate: (29.970).nullable,
    ));

    assert(playlist.toString() ==
        "#EXTM3U\n"
        ~ "#EXT-X-STREAM-INF:BANDWIDTH=3000000,AVERAGE-BANDWIDTH=2500000,CODECS=\"avc1.4d401e,mp4a.40.2\",RESOLUTION=1280x720,FRAME-RATE=29.970\n"
        ~ "video.m3u8\n"
    );
}

// Round-trip parse tests

/// basic round-trip
unittest
{
    string input =
        "#EXTM3U\n"
        ~ "#EXT-X-STREAM-INF:BANDWIDTH=1000000\n"
        ~ "low/index.m3u8\n"
        ~ "#EXT-X-STREAM-INF:BANDWIDTH=5000000\n"
        ~ "high/index.m3u8\n";

    assert(MasterPlaylist.fromString(input).toString() == input);
}

/// round-trip with codecs and resolution
unittest
{
    string input =
        "#EXTM3U\n"
        ~ "#EXT-X-STREAM-INF:BANDWIDTH=2560000,CODECS=\"avc1.4d401e,mp4a.40.2\",RESOLUTION=1280x720\n"
        ~ "720p/stream.m3u8\n"
        ~ "#EXT-X-STREAM-INF:BANDWIDTH=7680000,CODECS=\"avc1.4d401e,mp4a.40.2\",RESOLUTION=1920x1080\n"
        ~ "1080p/stream.m3u8\n";

    assert(MasterPlaylist.fromString(input).toString() == input);
}

/// round-trip with all attributes
unittest
{
    string input =
        "#EXTM3U\n"
        ~ "#EXT-X-STREAM-INF:BANDWIDTH=3000000,AVERAGE-BANDWIDTH=2500000,CODECS=\"avc1.4d401e,mp4a.40.2\",RESOLUTION=1280x720,FRAME-RATE=29.970\n"
        ~ "video.m3u8\n";

    assert(MasterPlaylist.fromString(input).toString() == input);
}

/// unknown tags are ignored
unittest
{
    string input =
        "#EXTM3U\n"
        ~ "#EXT-X-VERSION:3\n"
        ~ "#EXT-X-STREAM-INF:BANDWIDTH=1000000\n"
        ~ "low/index.m3u8\n";

    auto playlist = MasterPlaylist.fromString(input);
    assert(playlist.variants.length == 1);
    assert(playlist.variants[0].bandwidth == 1_000_000);
}
