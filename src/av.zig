const std = @import("std");
const c = @cImport({
    @cInclude("libavformat/avformat.h");
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libswscale/swscale.h");
    @cInclude("libavutil/imgutils.h");
});

pub const PIX_FMT_RGBA = c.AV_PIX_FMT_RGBA;
pub const SWS_BILINEAR = c.SWS_BILINEAR;
pub const MEDIA_TYPE_VIDEO = c.AVMEDIA_TYPE_VIDEO;
pub const MEDIA_TYPE_AUDIO = c.AVMEDIA_TYPE_AUDIO;

pub const Packet = c.AVPacket;
pub const Frame = c.AVFrame;

pub const FormatCtx = c.AVFormatContext;
pub const CodecCtx = c.struct_AVCodecContext;
pub const Stream = c.struct_AVStream;

pub fn open_video_file(file_path: []const u8) !*FormatCtx {
    var fmt_ctx: ?*c.AVFormatContext = null;
    if (c.avformat_open_input(&fmt_ctx, file_path.ptr, null, null) != 0)
        return error.CannotOpenFile;
    if (c.avformat_find_stream_info(fmt_ctx, null) < 0)
        return error.CannotFindStream;
    return fmt_ctx orelse error.CannotFindStream;
}

pub fn get_stream_ind(fmt_ctx: *c.AVFormatContext) !usize {
    var video_stream_index: c_int = -1;
    for (0..fmt_ctx.*.nb_streams) |i| {
        if (fmt_ctx.*.streams[i].*.codecpar.*.codec_type == c.AVMEDIA_TYPE_VIDEO) {
            video_stream_index = @intCast(i);
            break;
        }
    }
    if (video_stream_index == -1)
        return error.NoVideoStream;
    return @intCast(video_stream_index);
}

pub fn get_decoder(fmt_ctx: *c.AVFormatContext, video_stream_index: usize) !*CodecCtx {
    const codecpar = fmt_ctx.*.streams[@intCast(video_stream_index)].*.codecpar;
    const codec = c.avcodec_find_decoder(codecpar.*.codec_id) orelse return error.NoDecoder;

    const codec_ctx = c.avcodec_alloc_context3(codec);
    _ = c.avcodec_parameters_to_context(codec_ctx, codecpar);
    if (c.avcodec_open2(codec_ctx, codec, null) < 0)
        return error.CannotOpenDecoder;
    return codec_ctx;
}

pub fn frame_alloc() *Frame {
    return c.av_frame_alloc();
}

pub fn frame_free(frame: **Frame) void {
    return c.av_frame_free(@ptrCast(frame));
}

pub fn read_frame(fmt_ctx: *FormatCtx, packet: *Packet) c_int {
    return c.av_read_frame(fmt_ctx, packet);
}

pub fn send_packet(codec_ctx: *CodecCtx, packet: *Packet) c_int {
    return c.avcodec_send_packet(codec_ctx, packet);
}

pub fn packet_unref(packet: *Packet) void {
    c.av_packet_unref(packet);
}

pub fn receive_frame(codec_ctx: *CodecCtx, frame: *Frame) c_int {
    return c.avcodec_receive_frame(codec_ctx, frame);
}

pub const frame_get_buffer = c.av_frame_get_buffer;
pub const sws_scale = c.sws_scale;
pub const sws_get_context = c.sws_getContext;

pub const format_open_input = c.avformat_open_input;
pub const format_close_input = c.avformat_close_input;
pub const format_find_stream_info = c.avformat_find_stream_info;
