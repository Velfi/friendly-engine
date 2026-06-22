#ifndef FE_AUDIO_DECODE_H
#define FE_AUDIO_DECODE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FeDecodedAudio {
    float *samples;
    uint64_t frame_count;
    uint32_t channels;
    uint32_t sample_rate;
} FeDecodedAudio;

int fe_audio_decode_file(const char *path, FeDecodedAudio *out_audio);
void fe_audio_decoded_free(FeDecodedAudio *audio);

#ifdef __cplusplus
}
#endif

#endif
