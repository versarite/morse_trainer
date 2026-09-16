/*
 * Morse Code Trainer
 * -------------------
 * A self-contained Windows console application for learning and practicing
 * Morse code. Generates its own audio tones in software (a sine wave with
 * a short fade-in/out envelope to avoid clicks) and plays them through the
 * system's default audio output device via the Windows Multimedia API
 * (winmm / waveOut). This means it works with ANY generic sound card or
 * audio device Windows already knows about -- no special drivers, DSP
 * hardware, or third-party audio libraries required.
 *
 * Modes:
 *   1. Copy Practice        - plays a random character, you type what you
 *                              heard, and it tracks your accuracy.
 *   2. Koch Method Trainer  - adaptive trainer. Starts with just 2
 *                              characters (K, M) at full target speed and
 *                              adds a new character each time you clear a
 *                              round with >=90% accuracy, following the
 *                              classic Koch character order.
 *   3. Send / Playback      - type text and hear it played back in Morse,
 *      Practice               with the Morse pattern printed alongside so
 *                              you can learn how words "sound".
 *   4. Settings             - adjust character speed (WPM), Farnsworth
 *                              (effective) speed, and tone frequency.
 *
 * Build (MinGW-w64):
 *   gcc morse_trainer.c -o morse_trainer.exe -lwinmm -lm -O2
 *
 * Build (MSVC, "Developer Command Prompt"):
 *   cl morse_trainer.c winmm.lib
 *
 * See README.md for more detail.
 */

#ifndef _CRT_SECURE_NO_WARNINGS
#define _CRT_SECURE_NO_WARNINGS
#endif

#include <windows.h>
#include <mmsystem.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>
#include <time.h>
#include <conio.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* ------------------------------------------------------------------ */
/* Configuration constants                                            */
/* ------------------------------------------------------------------ */

#define SAMPLE_RATE     44100
#define AMPLITUDE       8000.0   /* headroom below +/-32767 to avoid clipping */
#define RAMP_MS         5.0      /* fade in/out to avoid audible clicks/pops */

/* ------------------------------------------------------------------ */
/* Morse code table                                                    */
/* ------------------------------------------------------------------ */

typedef struct {
    char ch;
    const char *code;
} MorseEntry;

static const MorseEntry MORSE_TABLE[] = {
    {'A', ".-"},    {'B', "-..."},  {'C', "-.-."},  {'D', "-.."},
    {'E', "."},     {'F', "..-."},  {'G', "--."},   {'H', "...."},
    {'I', ".."},    {'J', ".---"},  {'K', "-.-"},   {'L', ".-.."},
    {'M', "--"},    {'N', "-."},    {'O', "---"},   {'P', ".--."},
    {'Q', "--.-"},  {'R', ".-."},   {'S', "..."},   {'T', "-"},
    {'U', "..-"},   {'V', "...-"},  {'W', ".--"},   {'X', "-..-"},
    {'Y', "-.--"},  {'Z', "--.."},
    {'0', "-----"}, {'1', ".----"}, {'2', "..---"}, {'3', "...--"},
    {'4', "....-"}, {'5', "....."}, {'6', "-...."}, {'7', "--..."},
    {'8', "---.."}, {'9', "----."},
    {'.', ".-.-.-"},{',', "--..--"},{'?', "..--.."},{'/', "-..-."},
    {'=', "-...-"}
};
#define MORSE_TABLE_LEN (sizeof(MORSE_TABLE)/sizeof(MORSE_TABLE[0]))

/* Classic Koch method character order (K M R S U A P T L O W I . N J E F
 * 0 Y V G 5 Q 9 Z H 3 8 B ? 4 2 7 C 1 D 6 X). Levels grow left to right. */
static const char KOCH_ORDER[] = "KMRSUAPTLOWI.NJEF0YVG5Q9ZH38B?427C1D6X";
#define KOCH_MAX_LEVEL ((int)(sizeof(KOCH_ORDER) - 1))

static const char *MorseFor(char c) {
    size_t i;
    c = (char)toupper((unsigned char)c);
    for (i = 0; i < MORSE_TABLE_LEN; i++) {
        if (MORSE_TABLE[i].ch == c) return MORSE_TABLE[i].code;
    }
    return NULL;
}

/* ------------------------------------------------------------------ */
/* Trainer settings                                                    */
/* ------------------------------------------------------------------ */

typedef struct {
    int wpm;             /* character (element) speed in words per minute */
    int farnsworth_wpm;  /* effective spacing speed; <= wpm */
    double freq;          /* sidetone frequency in Hz */
} Settings;

/* ------------------------------------------------------------------ */
/* Growable 16-bit mono PCM audio buffer                              */
/* ------------------------------------------------------------------ */

typedef struct {
    short *data;
    DWORD count;     /* samples used */
    DWORD capacity;  /* samples allocated */
} AudioBuf;

static void AudioBufInit(AudioBuf *b) {
    b->data = NULL;
    b->count = 0;
    b->capacity = 0;
}

static void AudioBufFree(AudioBuf *b) {
    free(b->data);
    b->data = NULL;
    b->count = 0;
    b->capacity = 0;
}

static void AudioBufEnsure(AudioBuf *b, DWORD extra) {
    if (b->count + extra > b->capacity) {
        DWORD newCap = (b->capacity == 0) ? 4096 : b->capacity;
        while (newCap < b->count + extra) newCap *= 2;
        b->data = (short *)realloc(b->data, (size_t)newCap * sizeof(short));
        b->capacity = newCap;
    }
}

static void AudioBufAppendTone(AudioBuf *b, double freqHz, double durMs) {
    DWORD n = (DWORD)(SAMPLE_RATE * durMs / 1000.0);
    DWORD rampSamples = (DWORD)(SAMPLE_RATE * RAMP_MS / 1000.0);
    DWORD i;

    if (n == 0) return;
    if (rampSamples * 2 > n) rampSamples = n / 2;

    AudioBufEnsure(b, n);
    for (i = 0; i < n; i++) {
        double t = (double)i / SAMPLE_RATE;
        double amp = AMPLITUDE;
        double sample;

        if (rampSamples > 0) {
            if (i < rampSamples) amp *= (double)i / (double)rampSamples;
            else if (i >= n - rampSamples) amp *= (double)(n - i) / (double)rampSamples;
        }

        sample = amp * sin(2.0 * M_PI * freqHz * t);
        b->data[b->count + i] = (short)sample;
    }
    b->count += n;
}

static void AudioBufAppendSilence(AudioBuf *b, double durMs) {
    DWORD n = (DWORD)(SAMPLE_RATE * durMs / 1000.0);
    if (n == 0) return;
    AudioBufEnsure(b, n);
    memset(b->data + b->count, 0, (size_t)n * sizeof(short));
    b->count += n;
}

/* ------------------------------------------------------------------ */
/* Text -> Morse audio                                                 */
/* ------------------------------------------------------------------ */

/*
 * Standard timing: at W words-per-minute (based on the word "PARIS" as the
 * timing reference, 50 dit-units per word), one dit = 1200 / W ms, one dah
 * = 3 dits, inter-element gap (within a character) = 1 dit, inter-character
 * gap = 3 dits, inter-word gap = 7 dits.
 *
 * Farnsworth timing keeps individual dits/dahs at full "character speed"
 * (wpm) so the rhythm of each letter stays realistic, but stretches the
 * gaps between characters/words out to a slower "effective speed"
 * (farnsworth_wpm), which is easier for beginners to keep up with.
 */
static void BuildMorseAudio(AudioBuf *b, const char *text, const Settings *s) {
    double ditMs = 1200.0 / s->wpm;
    double dahMs = ditMs * 3.0;
    double elementGapMs = ditMs;                          /* within a character, at char speed */
    double spacingUnitMs = 1200.0 / s->farnsworth_wpm;     /* Farnsworth spacing unit */
    double charGapMs = spacingUnitMs * 3.0;
    double wordGapMs = spacingUnitMs * 7.0;
    const char *p;

    for (p = text; *p; p++) {
        char c = (char)toupper((unsigned char)*p);
        const char *code;
        size_t i, len;

        if (c == ' ') {
            AudioBufAppendSilence(b, wordGapMs);
            continue;
        }

        code = MorseFor(c);
        if (!code) continue; /* skip unsupported characters silently */

        len = strlen(code);
        for (i = 0; i < len; i++) {
            AudioBufAppendTone(b, s->freq, code[i] == '.' ? ditMs : dahMs);
            if (i + 1 < len) AudioBufAppendSilence(b, elementGapMs);
        }
        AudioBufAppendSilence(b, charGapMs);
    }
}

/* ------------------------------------------------------------------ */
/* Playback via winmm (works with the system's default sound device,   */
/* i.e. any generic sound card Windows already has a driver for)       */
/* ------------------------------------------------------------------ */

static void PlayAudio(const AudioBuf *b) {
    WAVEFORMATEX wfx;
    HWAVEOUT hWaveOut;
    HANDLE hEvent;
    WAVEHDR hdr;
    MMRESULT res;

    if (b->count == 0) return;

    memset(&wfx, 0, sizeof(wfx));
    wfx.wFormatTag = WAVE_FORMAT_PCM;
    wfx.nChannels = 1;
    wfx.nSamplesPerSec = SAMPLE_RATE;
    wfx.wBitsPerSample = 16;
    wfx.nBlockAlign = (WORD)(wfx.nChannels * wfx.wBitsPerSample / 8);
    wfx.nAvgBytesPerSec = wfx.nSamplesPerSec * wfx.nBlockAlign;

    hEvent = CreateEvent(NULL, FALSE, FALSE, NULL);
    if (!hEvent) { printf("Could not create audio sync event.\n"); return; }

    /* WAVE_MAPPER = "whatever the default output device is" -- this is
     * what makes the program work with any generic sound card without
     * needing to know its name or capabilities ahead of time. */
    res = waveOutOpen(&hWaveOut, WAVE_MAPPER, &wfx, (DWORD_PTR)hEvent, 0, CALLBACK_EVENT);
    if (res != MMSYSERR_NOERROR) {
        printf("Could not open an audio output device (error %d).\n", res);
        CloseHandle(hEvent);
        return;
    }

    memset(&hdr, 0, sizeof(hdr));
    hdr.lpData = (LPSTR)b->data;
    hdr.dwBufferLength = b->count * sizeof(short);

    waveOutPrepareHeader(hWaveOut, &hdr, sizeof(WAVEHDR));
    waveOutWrite(hWaveOut, &hdr, sizeof(WAVEHDR));

    while (!(hdr.dwFlags & WHDR_DONE)) {
        WaitForSingleObject(hEvent, INFINITE);
    }

    waveOutUnprepareHeader(hWaveOut, &hdr, sizeof(WAVEHDR));
    waveOutClose(hWaveOut);
    CloseHandle(hEvent);
}

static void PlayText(const char *text, const Settings *s) {
    AudioBuf buf;
    AudioBufInit(&buf);
    BuildMorseAudio(&buf, text, s);
    PlayAudio(&buf);
    AudioBufFree(&buf);
}

/* ------------------------------------------------------------------ */
/* Small input helpers                                                 */
/* ------------------------------------------------------------------ */

static void FlushStdin(void) {
    int c;
    while ((c = getchar()) != '\n' && c != EOF) { /* discard */ }
}

static int ReadIntInRange(const char *prompt, int lo, int hi, int fallback) {
    int v;
    printf("%s", prompt);
    if (scanf("%d", &v) != 1) { FlushStdin(); return fallback; }
    FlushStdin();
    if (v < lo || v > hi) {
        printf("  (out of range %d-%d, keeping previous value)\n", lo, hi);
        return fallback;
    }
    return v;
}

/* ------------------------------------------------------------------ */
/* Copy Practice: random single characters, immediate scoring          */
/* ------------------------------------------------------------------ */

static void CopyPractice(const Settings *s) {
    static const char CHARSET[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    int total = 0, correct = 0;
    size_t setLen = strlen(CHARSET);

    printf("\n--- Copy Practice ---\n");
    printf("Listen to each tone and type the character you heard.\n");
    printf("Press '!' at any time to end the session.\n\n");

    for (;;) {
        char c = CHARSET[rand() % setLen];
        char text[2] = { c, 0 };
        int ch;

        PlayText(text, s);

        printf("Your answer: ");
        ch = _getch();
        putchar((char)toupper(ch));
        putchar('\n');

        if (ch == '!') break;

        total++;
        if (toupper(ch) == c) {
            correct++;
            printf("  Correct!\n\n");
        } else {
            printf("  Incorrect -- it was '%c'.\n\n", c);
        }
    }

    if (total > 0) {
        printf("\nSession complete: %d/%d correct (%.1f%%)\n\n",
               correct, total, 100.0 * correct / total);
    } else {
        printf("\nNo characters attempted.\n\n");
    }
}

/* ------------------------------------------------------------------ */
/* Koch Method Trainer: adaptive character set, grows with accuracy    */
/* ------------------------------------------------------------------ */

static void KochTrainer(const Settings *s) {
    static int level = 2; /* persists across visits to this mode within a run */
    int total = 0, correct = 0;
    int roundSize = 20;
    int i;
    double acc;

    if (level > KOCH_MAX_LEVEL) level = KOCH_MAX_LEVEL;

    printf("\n--- Koch Method Trainer ---\n");
    printf("Practicing at %d WPM using characters: %.*s\n", s->wpm, level, KOCH_ORDER);
    printf("Listen and type each character. Score >=90%% to unlock the next one.\n");
    printf("Press '!' at any time to end the round early.\n\n");

    for (i = 0; i < roundSize; i++) {
        char c = KOCH_ORDER[rand() % level];
        char text[2] = { c, 0 };
        int ch;

        PlayText(text, s);

        printf("[%2d/%2d] Your answer: ", i + 1, roundSize);
        ch = _getch();
        putchar((char)toupper(ch));
        putchar('\n');

        if (ch == '!') break;

        total++;
        if (toupper(ch) == c) correct++;
    }

    acc = (total > 0) ? (100.0 * correct / total) : 0.0;
    printf("\nRound complete: %d/%d correct (%.1f%%)\n", correct, total, acc);

    if (total >= roundSize / 2 && acc >= 90.0 && level < KOCH_MAX_LEVEL) {
        level++;
        printf("Great job! Level up -> now practicing %d characters: %.*s\n\n",
               level, level, KOCH_ORDER);
    } else if (level >= KOCH_MAX_LEVEL) {
        printf("You've unlocked the full character set. Keep practicing for speed!\n\n");
    } else {
        printf("Keep practicing at this level: %.*s\n\n", level, KOCH_ORDER);
    }
}

/* ------------------------------------------------------------------ */
/* Send / Playback Practice: type text, hear it, see the pattern       */
/* ------------------------------------------------------------------ */

static int IEquals(const char *a, const char *b) {
    while (*a && *b) {
        if (toupper((unsigned char)*a) != toupper((unsigned char)*b)) return 0;
        a++; b++;
    }
    return *a == 0 && *b == 0;
}

static void SendPractice(const Settings *s) {
    char line[256];

    printf("\n--- Send / Playback Practice ---\n");
    printf("Type a word or phrase and it will be played back in Morse,\n");
    printf("with its pattern printed so you can learn how it sounds.\n");
    printf("Type 'exit' to return to the menu.\n\n");

    for (;;) {
        const char *p;
        printf("Text> ");
        if (!fgets(line, sizeof(line), stdin)) break;
        line[strcspn(line, "\n")] = 0;

        if (line[0] == 0) continue;
        if (IEquals(line, "exit")) break;

        printf("Morse: ");
        for (p = line; *p; p++) {
            char c = (char)toupper((unsigned char)*p);
            if (c == ' ') { printf(" / "); continue; }
            {
                const char *code = MorseFor(c);
                if (code) printf("%s ", code);
            }
        }
        printf("\n");

        PlayText(line, s);
        printf("\n");
    }
}

/* ------------------------------------------------------------------ */
/* Settings menu                                                       */
/* ------------------------------------------------------------------ */

static void SettingsMenu(Settings *s) {
    for (;;) {
        int choice;

        printf("\n--- Settings ---\n");
        printf("1. Character speed:        %d WPM\n", s->wpm);
        printf("2. Farnsworth speed:       %d WPM (effective spacing; <= character speed)\n", s->farnsworth_wpm);
        printf("3. Tone frequency:         %.0f Hz\n", s->freq);
        printf("4. Back to main menu\n");
        printf("Choice: ");

        if (scanf("%d", &choice) != 1) { FlushStdin(); continue; }
        FlushStdin();

        if (choice == 1) {
            char prompt[64];
            sprintf(prompt, "New character speed (5-40 WPM): ");
            s->wpm = ReadIntInRange(prompt, 5, 40, s->wpm);
            if (s->farnsworth_wpm > s->wpm) s->farnsworth_wpm = s->wpm;
        } else if (choice == 2) {
            char prompt[64];
            sprintf(prompt, "New Farnsworth speed (5-%d WPM): ", s->wpm);
            s->farnsworth_wpm = ReadIntInRange(prompt, 5, s->wpm, s->farnsworth_wpm);
        } else if (choice == 3) {
            double v;
            printf("New tone frequency (300-1200 Hz): ");
            if (scanf("%lf", &v) == 1) {
                FlushStdin();
                if (v >= 300.0 && v <= 1200.0) s->freq = v;
                else printf("  (out of range, keeping previous value)\n");
            } else {
                FlushStdin();
            }
        } else if (choice == 4) {
            break;
        } else {
            printf("Invalid choice.\n");
        }
    }
}

/* ------------------------------------------------------------------ */
/* Main menu                                                           */
/* ------------------------------------------------------------------ */

int main(void) {
    Settings s;
    s.wpm = 20;
    s.farnsworth_wpm = 20;
    s.freq = 700.0;

    srand((unsigned int)time(NULL));

    printf("=====================================\n");
    printf("       MORSE CODE TRAINER\n");
    printf("=====================================\n");
    printf("Uses your system's default audio output device --\n");
    printf("works with any standard sound card, no setup needed.\n");

    for (;;) {
        int choice;

        printf("\n-------------------------------------\n");
        printf("Speed: %d WPM (Farnsworth %d WPM)   Tone: %.0f Hz\n",
               s.wpm, s.farnsworth_wpm, s.freq);
        printf("1. Copy Practice (random characters)\n");
        printf("2. Koch Method Trainer (adaptive)\n");
        printf("3. Send / Playback Practice\n");
        printf("4. Settings\n");
        printf("5. Quit\n");
        printf("Choice: ");

        if (scanf("%d", &choice) != 1) { FlushStdin(); continue; }
        FlushStdin();

        switch (choice) {
            case 1: CopyPractice(&s); break;
            case 2: KochTrainer(&s); break;
            case 3: SendPractice(&s); break;
            case 4: SettingsMenu(&s); break;
            case 5: printf("73!\n"); return 0;
            default: printf("Invalid choice.\n"); break;
        }
    }
}
