#pragma once
#include <cstdint>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

// The bundled IR library uses mono, 44.1 kHz PCM WAV. Decode off the audio thread.
inline std::vector<int16_t> readExhaustResponse(const std::string &path) {
    std::ifstream input(path, std::ios::binary);
    auto u16 = [](const unsigned char *p) { return uint16_t(p[0] | p[1] << 8); };
    auto u32 = [](const unsigned char *p) { return uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24; };
    unsigned char header[12];
    if (!input.read(reinterpret_cast<char*>(header), 12) || std::memcmp(header,"RIFF",4) || std::memcmp(header+8,"WAVE",4))
        throw std::runtime_error("Missing or invalid exhaust response: " + path);
    int bits = 0;
    while (input) {
        unsigned char chunk[8];
        if (!input.read(reinterpret_cast<char*>(chunk), 8)) break;
        const uint32_t size = u32(chunk + 4);
        if (size > 16 * 1024 * 1024) break;
        if (!std::memcmp(chunk, "fmt ", 4)) {
            std::vector<unsigned char> fmt(size);
            if (size < 16 || !input.read(reinterpret_cast<char*>(fmt.data()), size)) break;
            bits = u16(fmt.data()+14);
            if (u16(fmt.data()) != 1 || u16(fmt.data()+2) != 1 || u32(fmt.data()+4) != 44100 || (bits != 16 && bits != 24))
                throw std::runtime_error("Unsupported exhaust response format");
        } else if (!std::memcmp(chunk, "data", 4) && bits) {
            const auto samples = std::min<uint32_t>(size / (bits/8), 10000);
            std::vector<int16_t> pcm(samples);
            for (auto &sample : pcm) {
                unsigned char bytes[3]{};
                if (!input.read(reinterpret_cast<char*>(bytes), bits/8)) throw std::runtime_error("Truncated exhaust response");
                sample = static_cast<int16_t>(u16(bytes + (bits == 24 ? 1 : 0)));
            }
            if (pcm.empty()) break;
            return pcm;
        } else input.seekg(size, std::ios::cur);
        if (size & 1) input.seekg(1, std::ios::cur);
    }
    throw std::runtime_error("Empty exhaust response: " + path);
}
