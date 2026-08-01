const fs = require('fs');
const path = require('path');

function writeWAV(filePath, samples, sampleRate = 44100) {
  const numChannels = 1;
  const bitsPerSample = 16;
  const byteRate = sampleRate * numChannels * bitsPerSample / 8;
  const blockAlign = numChannels * bitsPerSample / 8;
  const dataSize = samples.length * blockAlign;

  const buf = Buffer.alloc(44 + dataSize);
  // RIFF header
  buf.write('RIFF', 0);
  buf.writeUInt32LE(36 + dataSize, 4);
  buf.write('WAVE', 8);
  // fmt chunk
  buf.write('fmt ', 12);
  buf.writeUInt32LE(16, 16);        // chunk size
  buf.writeUInt16LE(1, 20);         // PCM
  buf.writeUInt16LE(numChannels, 22);
  buf.writeUInt32LE(sampleRate, 24);
  buf.writeUInt32LE(byteRate, 28);
  buf.writeUInt16LE(blockAlign, 32);
  buf.writeUInt16LE(bitsPerSample, 34);
  // data chunk
  buf.write('data', 36);
  buf.writeUInt32LE(dataSize, 40);
  for (let i = 0; i < samples.length; i++) {
    const val = Math.max(-32767, Math.min(32767, Math.round(samples[i] * 32767)));
    buf.writeInt16LE(val, 44 + i * 2);
  }
  fs.writeFileSync(filePath, buf);
}

const sr = 44100;
const outDir = path.join(__dirname, '健身训练手册');

// rest_start.wav — two descending tones, ~0.8s (enter rest between sets)
const startSamples = [];
for (let i = 0; i < sr * 0.8; i++) {
  const t = i / sr;
  const env = Math.max(0, 1 - t / 0.8);
  const freq = t < 0.4 ? 740 : 550;
  let val = env * 0.8 * Math.sin(2 * Math.PI * freq * t);
  val += env * 0.25 * Math.sin(2 * Math.PI * freq * 2 * t);
  startSamples.push(val * 0.5);
}
writeWAV(path.join(outDir, 'rest_start.wav'), startSamples);

// rest_end.wav — short ascending chime, ~0.5s (rest over, next set)
const endSamples = [];
for (let i = 0; i < sr * 0.5; i++) {
  const t = i / sr;
  const env = Math.exp(-t * 4);
  const freq = 660 + 330 * (t / 0.5);
  const val = env * Math.sin(2 * Math.PI * freq * t);
  endSamples.push(val * 0.5);
}
writeWAV(path.join(outDir, 'rest_end.wav'), endSamples);

// done.wav — triumphant three-note arpeggio, ~1.0s (workout finished)
const doneSamples = [];
for (let i = 0; i < sr * 1.0; i++) {
  const t = i / sr;
  const env = Math.max(0, 1 - t / 1.0);
  let freq = 523.25;            // C5
  if (t > 0.3) freq = 659.25;   // E5
  if (t > 0.6) freq = 783.99;   // G5
  let val = env * 0.8 * Math.sin(2 * Math.PI * freq * t);
  val += env * 0.3 * Math.sin(2 * Math.PI * freq * 1.5 * t);
  doneSamples.push(val * 0.45);
}
writeWAV(path.join(outDir, 'done.wav'), doneSamples);

console.log('OK',
  fs.statSync(path.join(outDir, 'rest_start.wav')).size,
  fs.statSync(path.join(outDir, 'rest_end.wav')).size,
  fs.statSync(path.join(outDir, 'done.wav')).size);
