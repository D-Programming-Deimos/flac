/* example decode module - Simple FLAC file decoder using libFLAC */
module decode;

/*
 * Copyright (C) 2007-2009  Josh Coalson
 * Copyright (C) 2011-2013  Xiph.Org Foundation
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

/*
 * This example shows how to use libFLAC to decode a FLAC file to a WAVE
 * file.  It only supports 16-bit stereo files.
 *
 * Complete API documentation can be found at:
 *   http://flac.sourceforge.net/api/
 */

import core.stdc.stdio;

import deimos.flac.all;

import std.conv;
import std.stdio;
import std.string;

alias stderr = std.stdio.stderr;

static FLAC__uint64 total_samples = 0;
static uint sample_rate       = 0;
static uint channels = 0;
static uint bps      = 0;

static FLAC__bool write_little_endian_uint16(FILE* f, FLAC__uint16 x)
{
    return
        fputc(x, f) != EOF &&
        fputc(x >> 8, f) != EOF
    ;
}

static FLAC__bool write_little_endian_int16(FILE* f, FLAC__int16 x)
{
    return write_little_endian_uint16(f, cast(FLAC__uint16)x);
}

static FLAC__bool write_little_endian_uint32(FILE* f, FLAC__uint32 x)
{
    return
        fputc(x, f) != EOF &&
        fputc(x >> 8, f) != EOF &&
        fputc(x >> 16, f) != EOF &&
        fputc(x >> 24, f) != EOF
    ;
}

int main(string[] args)
{
    auto argc() { return args.length; }
    alias argv = args;

    FLAC__bool ok = true;
    FLAC__StreamDecoder* decoder;
    FLAC__StreamDecoderInitStatus init_status;
    FILE* fout;

    if (argc != 3)
    {
        stderr.writefln("usage: %s infile.flac outfile.wav\n", argv[0]);
        return 1;
    }

    if ((fout = fopen(argv[2].toStringz, "wb")) is null)
    {
        stderr.writefln("ERROR: opening %s for output\n", argv[2]);
        return 1;
    }

    if ((decoder = FLAC__stream_decoder_new()) is null)
    {
        stderr.writefln("ERROR: allocating decoder\n");
        fclose(fout);
        return 1;
    }

    cast(void)FLAC__stream_decoder_set_md5_checking(decoder, true);

    init_status = FLAC__stream_decoder_init_file(decoder, argv[1].toStringz, cast(FLAC__StreamDecoderWriteCallback)&write_callback, cast(FLAC__StreamDecoderMetadataCallback)&metadata_callback, cast(FLAC__StreamDecoderErrorCallback)&error_callback, /*client_data=*/ cast(void*)fout);

    if (init_status != FLAC__StreamDecoderInitStatus.FLAC__STREAM_DECODER_INIT_STATUS_OK)
    {
        stderr.writefln("ERROR: initializing decoder: %s\n", FLAC__StreamDecoderInitStatusString[init_status]);
        ok = false;
    }

    if (ok)
    {
        ok = FLAC__stream_decoder_process_until_end_of_stream(decoder);
        stderr.writefln("decoding: %s\n", ok ? "succeeded" : "FAILED");

        // workaround for API mismatch
        const(char)*[10] data = *cast(const(char)*[10]*)&FLAC__StreamDecoderStateString;

        stderr.writefln("   state: %s\n", data[FLAC__stream_decoder_get_state(decoder)].to!string);
    }

    FLAC__stream_decoder_delete(decoder);
    fclose(fout);

    return 0;
}

extern(C) FLAC__StreamDecoderWriteStatus write_callback(const FLAC__StreamDecoder* decoder, const FLAC__Frame* frame, const FLAC__int32** buffer, void* client_data)
{
    FILE* f = cast(FILE*)client_data;
    const FLAC__uint32 total_size = cast(FLAC__uint32)(total_samples * channels * (bps / 8));
    size_t i;

    cast(void)decoder;

    if (total_samples == 0)
    {
        stderr.writefln("ERROR: this example only works for FLAC files that have a total_samples count in STREAMINFO\n");
        return FLAC__StreamDecoderWriteStatus.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    }

    if (channels != 2 || bps != 16)
    {
        stderr.writefln("ERROR: this example only supports 16bit stereo streams\n");
        return FLAC__StreamDecoderWriteStatus.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    }

    /* write WAVE header before we write the first frame */
    if (frame.header.number.sample_number == 0)
    {
        if (
            fwrite("RIFF".toStringz, 1, 4, f) < 4 ||
            !write_little_endian_uint32(f, total_size + 36) ||
            fwrite("WAVEfmt ".toStringz, 1, 8, f) < 8 ||
            !write_little_endian_uint32(f, 16) ||
            !write_little_endian_uint16(f, 1) ||
            !write_little_endian_uint16(f, cast(FLAC__uint16)channels) ||
            !write_little_endian_uint32(f, sample_rate) ||
            !write_little_endian_uint32(f, sample_rate * channels * (bps / 8)) ||
            !write_little_endian_uint16(f, cast(FLAC__uint16)(channels * (bps / 8))) ||           /* block align */
            !write_little_endian_uint16(f, cast(FLAC__uint16)bps) ||
            fwrite("data".toStringz, 1, 4, f) < 4 ||
            !write_little_endian_uint32(f, total_size)
            )
        {
            stderr.writefln("ERROR: write error\n");
            return FLAC__StreamDecoderWriteStatus.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
        }
    }

    /* write decoded PCM samples */
    for (i = 0; i < frame.header.blocksize; i++)
    {
        if (
            !write_little_endian_int16(f, cast(FLAC__int16)buffer[0][i]) ||              /* left channel */
            !write_little_endian_int16(f, cast(FLAC__int16)buffer[1][i])                 /* right channel */
            )
        {
            stderr.writefln("ERROR: write error\n");
            return FLAC__StreamDecoderWriteStatus.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
        }
    }

    return FLAC__StreamDecoderWriteStatus.FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
}

extern(C) void metadata_callback(const FLAC__StreamDecoder* decoder, const FLAC__StreamMetadata* metadata, void* client_data)
{
    //~ cast(void)decoder, cast(void)client_data;

    /* print some stats */
    if (metadata.type == FLAC__MetadataType.FLAC__METADATA_TYPE_STREAMINFO)
    {
        /* save for later */
        total_samples = metadata.data.stream_info.total_samples;
        sample_rate   = metadata.data.stream_info.sample_rate;
        channels      = metadata.data.stream_info.channels;
        bps = metadata.data.stream_info.bits_per_sample;

        stderr.writefln("sample rate    : %s Hz\n", sample_rate);
        stderr.writefln("channels       : %s\n", channels);
        stderr.writefln("bits per sample: %s\n", bps);
        stderr.writefln("total samples  : %s\n", total_samples);
    }
}

extern(C) void error_callback(const FLAC__StreamDecoder* decoder, FLAC__StreamDecoderErrorStatus status, void* client_data)
{
    stderr.writefln("Got error callback: %s\n", FLAC__StreamDecoderErrorStatusString[status]);
}
