/**
 * Shared parsing utilities for HLS m3u8 playlists.
 *
 * Authors: Hiroki Noda
 * Copyright: Copyright © 2026 Hiroki Noda
 * License: BSL-1.0
*/
module hls_m3u8.parse_utils;

private import core.time : dur, Duration;

private import std.conv : ConvException, to;
private import std.math : lround;
private import std.typecons : Nullable, nullable;

public import hls_m3u8.media_segment : ByteRange;

@safe:

/// Exception thrown when parsing an m3u8 playlist fails.
class M3U8ParseException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}

/**
 * Parse an EXTINF duration value.
 * Supports both integer (v1/v2) and decimal-floating-point (v3+) formats.
 */
Duration parseExtinfDuration(string value)
{
    import std.algorithm : findSplit;
    import std.string : strip;

    auto parts = value.findSplit(",");
    string durStr = parts[0].strip;

    if (durStr.length == 0)
        throw new M3U8ParseException("empty EXTINF duration");

    try
    {
        double val = durStr.to!double;
        return dur!"msecs"(lround(val * 1000));
    }
    catch (ConvException e)
    {
        throw new M3U8ParseException("invalid EXTINF duration: " ~ durStr);
    }
}

/**
 * Parse a byte range string like "1024" or "1024@0".
 */
ByteRange parseByteRange(string value)
{
    import std.algorithm : findSplit;

    auto parts = value.findSplit("@");
    try
    {
        if (parts[1].length == 0)
            return ByteRange(length: parts[0].to!ulong);
        else
            return ByteRange(length: parts[0].to!ulong, offset: parts[2].to!ulong.nullable);
    }
    catch (ConvException e)
    {
        throw new M3U8ParseException("invalid byte range: " ~ value);
    }
}

/**
 * Parse an HLS attribute list string.
 * Handles quoted-string values containing commas (e.g. CODECS).
 * Returns an associative array of attribute name to value (quotes stripped).
 */
string[string] parseAttributeList(string attrStr)
{
    string[string] result;
    bool inQuote = false;
    bool parsingValue = false;
    string currentKey;
    string currentValue;

    foreach (c; attrStr)
    {
        if (c == '"')
        {
            inQuote = !inQuote;
        }
        else if (c == '=' && !inQuote && !parsingValue)
        {
            parsingValue = true;
        }
        else if (c == ',' && !inQuote)
        {
            result[currentKey] = currentValue;
            currentKey = "";
            currentValue = "";
            parsingValue = false;
        }
        else
        {
            if (parsingValue)
                currentValue ~= c;
            else
                currentKey ~= c;
        }
    }

    if (currentKey.length > 0)
        result[currentKey] = currentValue;

    return result;
}

/**
 * Parse a 128-bit hex IV string (e.g. "0x00000000000000000000000000000001").
 */
ubyte[16] parseHexIV(string hexStr)
{
    if (hexStr.length < 2 || (hexStr[0 .. 2] != "0x" && hexStr[0 .. 2] != "0X"))
        throw new M3U8ParseException("IV must start with 0x or 0X");
    hexStr = hexStr[2 .. $];

    if (hexStr.length != 32)
        throw new M3U8ParseException("invalid IV length: expected 32 hex digits");

    ubyte[16] result;
    try
        foreach (i; 0 .. 16)
            result[i] = hexStr[i * 2 .. i * 2 + 2].to!ubyte(16);
    catch (ConvException e)
        throw new M3U8ParseException("invalid hex digit in IV");
    return result;
}

///
unittest
{
    import core.time : seconds, msecs;

    // decimal duration (v3+)
    assert(parseExtinfDuration("10.000,") == 10.seconds);
    assert(parseExtinfDuration("9.967,") == 9967.msecs);
    assert(parseExtinfDuration("3.000,title") == 3.seconds);

    // integer duration (v1/v2)
    assert(parseExtinfDuration("10,") == 10.seconds);

    // no trailing comma
    assert(parseExtinfDuration("5.000") == 5.seconds);
}

///
unittest
{
    auto br1 = parseByteRange("1024");
    assert(br1.length == 1024);
    assert(br1.offset.isNull);

    auto br2 = parseByteRange("1024@0");
    assert(br2.length == 1024);
    assert(br2.offset.get == 0);

    auto br3 = parseByteRange("15000@10000");
    assert(br3.length == 15000);
    assert(br3.offset.get == 10000);
}

///
unittest
{
    auto attrs = parseAttributeList(`METHOD=AES-128,URI="key.bin",IV=0x00000000000000000000000000000001`);
    assert(attrs["METHOD"] == "AES-128");
    assert(attrs["URI"] == "key.bin");
    assert(attrs["IV"] == "0x00000000000000000000000000000001");

    // quoted value with commas
    auto attrs2 = parseAttributeList(`BANDWIDTH=2560000,CODECS="avc1.4d401e,mp4a.40.2",RESOLUTION=1280x720`);
    assert(attrs2["BANDWIDTH"] == "2560000");
    assert(attrs2["CODECS"] == "avc1.4d401e,mp4a.40.2");
    assert(attrs2["RESOLUTION"] == "1280x720");
}

///
unittest
{
    auto iv = parseHexIV("0x00000000000000000000000000000001");
    ubyte[16] expected = 0;
    expected[15] = 1;
    assert(iv == expected);

    auto iv2 = parseHexIV("0xFF000000000000000000000000000000");
    assert(iv2[0] == 0xFF);
    assert(iv2[1] == 0);
}
