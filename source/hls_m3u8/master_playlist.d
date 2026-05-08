/**
 * The master playlist of [HLS](https://datatracker.ietf.org/doc/html/rfc8216).
 *
 * Authors: Hiroki Noda
 * Copyright: Copyright © 2026 Hiroki Noda
 * License: BSL-1.0
*/
module hls_m3u8.master_playlist;

private import std.array : appender;
private import std.format : format;
private import std.typecons : Nullable;

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
    string serialize()
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
    string serialize()
    {
        auto buf = appender!string;
        buf ~= "#EXTM3U\n";

        foreach (variant; variants)
        {
            buf ~= variant.serialize();
        }

        return buf[];
    }
}

///
unittest
{
    auto playlist = MasterPlaylist();
    playlist.addVariant(VariantStream("low/index.m3u8", bandwidth: 1_000_000));
    playlist.addVariant(VariantStream("high/index.m3u8", bandwidth: 5_000_000));

    assert(playlist.serialize() ==
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

    assert(playlist.serialize() ==
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

    assert(playlist.serialize() ==
        "#EXTM3U\n"
        ~ "#EXT-X-STREAM-INF:BANDWIDTH=3000000,AVERAGE-BANDWIDTH=2500000,CODECS=\"avc1.4d401e,mp4a.40.2\",RESOLUTION=1280x720,FRAME-RATE=29.970\n"
        ~ "video.m3u8\n"
    );
}
