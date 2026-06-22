#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include <stdlib.h>
#include <string.h>

#include "fe_audio_decode.h"

extern int stb_vorbis_decode_filename(const char *filename, int *channels, int *sample_rate, short **output);

static int fe_has_extension(const char *path, const char *extension) {
    const size_t path_len = strlen(path);
    const size_t ext_len = strlen(extension);
    if (path_len < ext_len) return 0;
    const char *tail = path + path_len - ext_len;
    for (size_t i = 0; i < ext_len; i += 1) {
        char a = tail[i];
        char b = extension[i];
        if (a >= 'A' && a <= 'Z') a = (char)(a - 'A' + 'a');
        if (b >= 'A' && b <= 'Z') b = (char)(b - 'A' + 'a');
        if (a != b) return 0;
    }
    return 1;
}

static int fe_decode_ogg_file(const char *path, FeDecodedAudio *out_audio) {
    int channels = 0;
    int sample_rate = 0;
    short *source = NULL;
    const int frames = stb_vorbis_decode_filename(path, &channels, &sample_rate, &source);
    if (frames <= 0 || channels <= 0 || sample_rate <= 0 || source == NULL) {
        return -1;
    }

    const uint64_t sample_count = (uint64_t)frames * (uint64_t)channels;
    if (sample_count > (UINT64_MAX / sizeof(float))) {
        free(source);
        return -2;
    }

    float *samples = (float *)malloc((size_t)sample_count * sizeof(float));
    if (samples == NULL) {
        free(source);
        return -3;
    }

    for (uint64_t i = 0; i < sample_count; i += 1) {
        samples[i] = (float)source[i] / 32768.0f;
    }

    free(source);
    out_audio->samples = samples;
    out_audio->frame_count = (uint64_t)frames;
    out_audio->channels = (uint32_t)channels;
    out_audio->sample_rate = (uint32_t)sample_rate;
    return 0;
}

static int fe_decode_miniaudio_file(const char *path, FeDecodedAudio *out_audio) {
    ma_decoder_config config = ma_decoder_config_init(ma_format_f32, 0, 0);
    ma_decoder decoder;
    ma_result result = ma_decoder_init_file(path, &config, &decoder);
    if (result != MA_SUCCESS) return -1;

    ma_format format = ma_format_unknown;
    ma_uint32 channels = 0;
    ma_uint32 sample_rate = 0;
    result = ma_decoder_get_data_format(&decoder, &format, &channels, &sample_rate, NULL, 0);
    if (result != MA_SUCCESS || format != ma_format_f32 || channels == 0 || sample_rate == 0) {
        ma_decoder_uninit(&decoder);
        return -2;
    }

    ma_uint64 frame_count = 0;
    result = ma_decoder_get_length_in_pcm_frames(&decoder, &frame_count);
    if (result != MA_SUCCESS || frame_count == 0) {
        ma_decoder_uninit(&decoder);
        return -3;
    }

    if (frame_count > (UINT64_MAX / channels / sizeof(float))) {
        ma_decoder_uninit(&decoder);
        return -4;
    }

    const uint64_t sample_count = (uint64_t)frame_count * (uint64_t)channels;
    float *samples = (float *)malloc((size_t)sample_count * sizeof(float));
    if (samples == NULL) {
        ma_decoder_uninit(&decoder);
        return -5;
    }

    ma_uint64 frames_read = 0;
    result = ma_decoder_read_pcm_frames(&decoder, samples, frame_count, &frames_read);
    ma_decoder_uninit(&decoder);
    if (result != MA_SUCCESS || frames_read == 0) {
        free(samples);
        return -6;
    }

    out_audio->samples = samples;
    out_audio->frame_count = (uint64_t)frames_read;
    out_audio->channels = (uint32_t)channels;
    out_audio->sample_rate = (uint32_t)sample_rate;
    return 0;
}

int fe_audio_decode_file(const char *path, FeDecodedAudio *out_audio) {
    if (path == NULL || out_audio == NULL) return -1;
    out_audio->samples = NULL;
    out_audio->frame_count = 0;
    out_audio->channels = 0;
    out_audio->sample_rate = 0;

    if (fe_has_extension(path, ".ogg")) {
        return fe_decode_ogg_file(path, out_audio);
    }

    return fe_decode_miniaudio_file(path, out_audio);
}

void fe_audio_decoded_free(FeDecodedAudio *audio) {
    if (audio == NULL) return;
    free(audio->samples);
    audio->samples = NULL;
    audio->frame_count = 0;
    audio->channels = 0;
    audio->sample_rate = 0;
}
