/**
 * keys.h
 *
 * Here you must place the keys for each mogg version that you would like to
 * decrypt, else leave the empty array. You can find the key for 0x0B in the
 * released source to SongCrypt by xorloser.
 *
 * As the keys are not mine, I cannot include them here.
 */

const unsigned char ctrKey0B[16] = {
 0x37, 0xB2, 0xE2, 0xB9, 0x1C, 0x74, 0xFA, 0x9E, 0x38, 0x81, 0x08, 0xEA, 0x36, 0x23, 0xDB, 0xE4
};

#ifndef RB1

const unsigned char HvKeys[80] = {
 0x01, 0x22, 0x00, 0x38, 0xD2, 0x01, 0x78, 0x8B, 0xDD, 0xCD, 0xD0, 0xF0, 0xFE, 0x3E, 0x24, 0x7F,
 0x51, 0x73, 0xAD, 0xE5, 0xB3, 0x99, 0xB8, 0x61, 0x58, 0x1A, 0xF9, 0xB8, 0x1E, 0xA7, 0xBE, 0xBF,
 0xC6, 0x22, 0x94, 0x30, 0xD8, 0x3C, 0x84, 0x14, 0x08, 0x73, 0x7C, 0xF2, 0x23, 0xF6, 0xEB, 0x5A,
 0x02, 0x1A, 0x83, 0xF3, 0x97, 0xE9, 0xD4, 0xB8, 0x06, 0x74, 0x14, 0x6B, 0x30, 0x4C, 0x00, 0x91,
 0x42, 0x66, 0x37, 0xB3, 0x68, 0x05, 0x9F, 0x85, 0x6E, 0x96, 0xBD, 0x1E, 0xF9, 0x0E, 0x7F, 0xBD
};

const unsigned char hiddenKeys[384] = {
 0x7F, 0x95, 0x5B, 0x9D, 0x94, 0xBA, 0x12, 0xF1, 0xD7, 0x5A, 0x67, 0xD9, 0x16, 0x45, 0x28, 0xDD, 
 0x61, 0x55, 0x55, 0xAF, 0x23, 0x91, 0xD6, 0x0A, 0x3A, 0x42, 0x81, 0x18, 0xB4, 0xF7, 0xF3, 0x04, 
 0x78, 0x96, 0x5D, 0x92, 0x92, 0xB0, 0x47, 0xAC, 0x8F, 0x5B, 0x6D, 0xDC, 0x1C, 0x41, 0x7E, 0xDA, 
 0x6A, 0x55, 0x53, 0xAF, 0x20, 0xC8, 0xDC, 0x0A, 0x66, 0x43, 0xDD, 0x1C, 0xB2, 0xA5, 0xA4, 0x0C, 
 0x7E, 0x92, 0x5C, 0x93, 0x90, 0xED, 0x4A, 0xAD, 0x8B, 0x07, 0x36, 0xD3, 0x10, 0x41, 0x78, 0x8F, 
 0x60, 0x08, 0x55, 0xA8, 0x26, 0xCF, 0xD0, 0x0F, 0x65, 0x11, 0x84, 0x45, 0xB1, 0xA0, 0xFA, 0x57, 
 0x79, 0x97, 0x0B, 0x90, 0x92, 0xB0, 0x44, 0xAD, 0x8A, 0x0E, 0x60, 0xD9, 0x14, 0x11, 0x7E, 0x8D, 
 0x35, 0x5D, 0x5C, 0xFB, 0x21, 0x9C, 0xD3, 0x0E, 0x32, 0x40, 0xD1, 0x48, 0xB8, 0xA7, 0xA1, 0x0D, 
 0x28, 0xC3, 0x5D, 0x97, 0xC1, 0xEC, 0x42, 0xF1, 0xDC, 0x5D, 0x37, 0xDA, 0x14, 0x47, 0x79, 0x8A, 
 0x32, 0x5C, 0x54, 0xF2, 0x72, 0x9D, 0xD3, 0x0D, 0x67, 0x4C, 0xD6, 0x49, 0xB4, 0xA2, 0xF3, 0x50, 
 0x28, 0x96, 0x5E, 0x95, 0xC5, 0xE9, 0x45, 0xAD, 0x8A, 0x5D, 0x64, 0x8E, 0x17, 0x40, 0x2E, 0x87, 
 0x36, 0x58, 0x06, 0xFD, 0x75, 0x90, 0xD0, 0x5F, 0x3A, 0x40, 0xD4, 0x4C, 0xB0, 0xF7, 0xA7, 0x04, 
 0x2C, 0x96, 0x01, 0x96, 0x9B, 0xBC, 0x15, 0xA6, 0xDE, 0x0E, 0x65, 0x8D, 0x17, 0x47, 0x2F, 0xDD, 
 0x63, 0x54, 0x55, 0xAF, 0x76, 0xCA, 0x84, 0x5F, 0x62, 0x44, 0x80, 0x4A, 0xB3, 0xF4, 0xF4, 0x0C, 
 0x7E, 0xC4, 0x0E, 0xC6, 0x9A, 0xEB, 0x43, 0xA0, 0xDB, 0x0A, 0x64, 0xDF, 0x1C, 0x42, 0x24, 0x89, 
 0x63, 0x5C, 0x55, 0xF3, 0x71, 0x90, 0xDC, 0x5D, 0x60, 0x40, 0xD1, 0x4D, 0xB2, 0xA3, 0xA7, 0x0D, 
 0x2C, 0x9A, 0x0B, 0x90, 0x9A, 0xBE, 0x47, 0xA7, 0x88, 0x5A, 0x6D, 0xDF, 0x13, 0x1D, 0x2E, 0x8B, 
 0x60, 0x5E, 0x55, 0xF2, 0x74, 0x9C, 0xD7, 0x0E, 0x60, 0x40, 0x80, 0x1C, 0xB7, 0xA1, 0xF4, 0x02, 
 0x28, 0x96, 0x5B, 0x95, 0xC1, 0xE9, 0x40, 0xA3, 0x8F, 0x0C, 0x32, 0xDF, 0x43, 0x1D, 0x24, 0x8D, 
 0x61, 0x09, 0x54, 0xAB, 0x27, 0x9A, 0xD3, 0x58, 0x60, 0x16, 0x84, 0x4F, 0xB3, 0xA4, 0xF3, 0x0D, 
 0x25, 0x93, 0x08, 0xC0, 0x9A, 0xBD, 0x10, 0xA2, 0xD6, 0x09, 0x60, 0x8F, 0x11, 0x1D, 0x7A, 0x8F, 
 0x63, 0x0B, 0x5D, 0xF2, 0x21, 0xEC, 0xD7, 0x08, 0x62, 0x40, 0x84, 0x49, 0xB0, 0xAD, 0xF2, 0x07, 
 0x29, 0xC3, 0x0C, 0x96, 0x96, 0xEB, 0x10, 0xA0, 0xDA, 0x59, 0x32, 0xD3, 0x17, 0x41, 0x25, 0xDC, 
 0x63, 0x08, 0x04, 0xAE, 0x77, 0xCB, 0x84, 0x5A, 0x60, 0x4D, 0xDD, 0x45, 0xB5, 0xF4, 0xA0, 0x05 
};

const unsigned char hiddenKeys_DM[384] = {
 0x53, 0xB6, 0x2E, 0xF4, 0xE7, 0xEC, 0x46, 0x0A, 0xD2, 0xA7, 0x9A, 0xB7, 0x6F, 0x00, 0xB6, 0xE8,
 0x04, 0x6D, 0x28, 0xD0, 0xF3, 0xAF, 0xA6, 0x5D, 0xE5, 0x27, 0xB9, 0x06, 0xB6, 0x69, 0xA2, 0xD6,
 0x1B, 0xF1, 0x33, 0x88, 0xC6, 0xCE, 0x99, 0xF8, 0x72, 0x3A, 0x39, 0x94, 0xDC, 0x59, 0x74, 0x9C,
 0x41, 0x91, 0x65, 0xC9, 0x55, 0xD6, 0x4C, 0xA6, 0x52, 0x05, 0xD7, 0xAB, 0xE9, 0xDA, 0x3D, 0x5C,
 0xDA, 0x56, 0x1B, 0xB6, 0x2B, 0xC1, 0x22, 0x91, 0x06, 0xB2, 0xA6, 0x5C, 0xBC, 0x4F, 0x50, 0x4B,
 0x3D, 0x6A, 0x11, 0xCD, 0xCA, 0xEA, 0xAB, 0x5B, 0x69, 0x8C, 0xBF, 0x93, 0xD3, 0xF7, 0x55, 0xE6,
 0x73, 0x92, 0xC9, 0xD9, 0xE3, 0x52, 0x5D, 0x56, 0x74, 0x73, 0xF8, 0xAA, 0xCF, 0xCB, 0xEF, 0x5D,
 0xE9, 0xC8, 0x97, 0x96, 0xDC, 0x7E, 0xC7, 0xF7, 0xD4, 0x83, 0x9B, 0x9D, 0x90, 0x06, 0xB5, 0x60,
 0x77, 0x99, 0xA9, 0x0F, 0x83, 0x9B, 0x1A, 0xDD, 0xBC, 0x60, 0x53, 0xEE, 0xF4, 0xFA, 0x77, 0x96,
 0xD0, 0x0F, 0x8F, 0x4B, 0xBB, 0x2E, 0x83, 0xF5, 0x19, 0x27, 0xC2, 0xA8, 0x10, 0x40, 0xF0, 0xF3,
 0xAA, 0xE1, 0x9D, 0xF1, 0x60, 0x38, 0xF9, 0xE1, 0x34, 0x10, 0xA7, 0x85, 0xE3, 0x9A, 0x77, 0xC7,
 0x11, 0x9C, 0xEB, 0x71, 0x71, 0xC1, 0x2B, 0x0E, 0x95, 0x2E, 0x0C, 0xA7, 0x94, 0x69, 0x0B, 0x56,
 0x86, 0x62, 0xF2, 0x77, 0xD0, 0x33, 0x90, 0x58, 0xF8, 0x22, 0xE3, 0xDD, 0x48, 0xB4, 0x98, 0xFE,
 0x9E, 0xDF, 0x47, 0x72, 0xA8, 0x38, 0x15, 0x3D, 0x8B, 0x11, 0xE3, 0xDD, 0xFF, 0xF9, 0x54, 0x9D,
 0xA3, 0x2E, 0xE6, 0x54, 0x34, 0x94, 0x8F, 0x3D, 0x6C, 0x78, 0xC0, 0x06, 0x28, 0xE9, 0x84, 0x5A,
 0x80, 0xB8, 0xBE, 0xBB, 0x03, 0xB1, 0x1B, 0xB6, 0xDC, 0xB6, 0x4C, 0xD5, 0xE2, 0xBF, 0x78, 0x2F,
 0x35, 0x81, 0x86, 0xC9, 0x42, 0xCB, 0x1B, 0x2B, 0x87, 0x32, 0xAE, 0x98, 0x73, 0x8E, 0xCE, 0x02,
 0xA7, 0x88, 0x2C, 0xBE, 0xFA, 0x54, 0x9D, 0x84, 0xBE, 0xC4, 0x0B, 0xFF, 0xE6, 0xD9, 0x18, 0x2E,
 0xCA, 0x53, 0xB0, 0x5F, 0x14, 0x3A, 0x40, 0xB2, 0x5F, 0x8D, 0x5E, 0x10, 0x86, 0x0D, 0x63, 0xBD,
 0xC7, 0x4B, 0x71, 0xD6, 0xFF, 0xDD, 0x2D, 0x1F, 0xD9, 0x06, 0x20, 0xF6, 0xF8, 0x2F, 0x7D, 0x56,
 0x40, 0x2F, 0x93, 0x66, 0x9B, 0xEE, 0x29, 0x5C, 0x91, 0xCF, 0xA6, 0xAD, 0x47, 0x63, 0x01, 0x87,
 0x51, 0x6C, 0xE8, 0x29, 0x55, 0x68, 0x5E, 0x11, 0xC2, 0x48, 0x23, 0x96, 0x05, 0x78, 0xB3, 0xA1,
 0x8F, 0xFB, 0x7E, 0xAD, 0x69, 0x6A, 0x24, 0xCD, 0x03, 0x97, 0xCA, 0xB8, 0x48, 0x39, 0xF6, 0xDD,
 0x56, 0x80, 0x61, 0xE7, 0x66, 0xEE, 0x5C, 0x55, 0xD1, 0x52, 0x57, 0xCE, 0xD2, 0xC0, 0xBE, 0xC1
};

const unsigned char hiddenKeys_Audica[384] = {
  0x9E, 0xDF, 0xA5, 0xBB, 0x02, 0xCA, 0x0C, 0x2B, 0x51, 0x02, 0x1A, 0x35, 0x11, 0x62, 0x8A, 0x0F,
  0x66, 0x31, 0x6E, 0x73, 0x0A, 0x68, 0x5F, 0x55, 0xE0, 0x51, 0x4F, 0x73, 0x50, 0x53, 0xB4, 0x9C,
  0x98, 0x3A, 0xFA, 0x87, 0x4C, 0x44, 0x70, 0xA8, 0x15, 0xE4, 0x5A, 0x85, 0x73, 0xAE, 0x1A, 0x32,
  0x26, 0x63, 0x28, 0x11, 0x4D, 0x80, 0x73, 0xAB, 0x3D, 0x86, 0x9C, 0x03, 0x99, 0xAC, 0x10, 0x1A,
  0xA4, 0xB6, 0xA4, 0xFC, 0x5A, 0xEC, 0x7A, 0x18, 0xC0, 0x2C, 0x79, 0x74, 0xE2, 0xDB, 0x35, 0x14,
  0x02, 0xFE, 0x91, 0x0E, 0x13, 0xA9, 0x44, 0xDF, 0x94, 0x85, 0x3F, 0x9A, 0x41, 0xCB, 0x34, 0x32,
  0x7B, 0x87, 0xC0, 0xF6, 0xAE, 0xF6, 0x44, 0x10, 0xD2, 0x01, 0xAF, 0x18, 0x67, 0x98, 0xC2, 0x0E,
  0xEC, 0x9A, 0x41, 0x42, 0xEA, 0x90, 0xEF, 0xDE, 0xD6, 0xBF, 0x12, 0x6C, 0x8B, 0x2B, 0x6E, 0x13,
  0x63, 0xE9, 0xB0, 0x24, 0xD2, 0x0F, 0xC1, 0x3C, 0x6F, 0x60, 0xEC, 0xD6, 0xCE, 0x9A, 0xCC, 0x7D,
  0x25, 0x04, 0x95, 0x81, 0x9D, 0xB9, 0xA9, 0xF1, 0x8B, 0x82, 0x1F, 0xF9, 0xA3, 0xA6, 0x2B, 0x3A,
  0xC1, 0x5D, 0xA1, 0xD2, 0x49, 0x92, 0x02, 0x8D, 0x76, 0x7A, 0x32, 0x76, 0xB7, 0xFD, 0x64, 0xCB,
  0x51, 0x2D, 0x51, 0xC7, 0xFC, 0x0E, 0x2F, 0xA4, 0xF8, 0x1D, 0xF1, 0x02, 0x81, 0x88, 0x49, 0x4F,
  0x0A, 0xFC, 0xCB, 0x82, 0x34, 0xAD, 0x23, 0xDB, 0x13, 0x1B, 0x4B, 0x7A, 0xA4, 0xD6, 0x26, 0xFA,
  0xDF, 0x86, 0x65, 0x64, 0xB0, 0x6F, 0x95, 0x84, 0x92, 0xD0, 0x4D, 0x31, 0x68, 0x61, 0x56, 0x21,
  0xDF, 0x60, 0xEE, 0xDB, 0xC5, 0x55, 0x26, 0xC0, 0x0E, 0x3F, 0xA8, 0x4B, 0xD4, 0xB1, 0x54, 0x3F,
  0x60, 0x93, 0xBF, 0xB3, 0x8A, 0x46, 0x79, 0x34, 0x36, 0xA9, 0x16, 0x9D, 0x20, 0xF7, 0xD3, 0x61,
  0x92, 0x63, 0x1E, 0x54, 0xE4, 0xDF, 0x9B, 0x42, 0x32, 0xB4, 0xA8, 0x3D, 0x2E, 0x48, 0x3A, 0x96,
  0x89, 0x0F, 0xCF, 0xAA, 0x22, 0x09, 0x1D, 0xD3, 0xF9, 0x28, 0x25, 0xCE, 0x67, 0x57, 0xD6, 0xD0,
  0xC1, 0x30, 0x1D, 0x91, 0xA1, 0xB7, 0x39, 0x1E, 0xE4, 0xD9, 0x08, 0x88, 0xCD, 0x19, 0x88, 0x09,
  0xFC, 0xC1, 0x38, 0x59, 0x7C, 0x4B, 0xD7, 0xD9, 0xF5, 0x10, 0xA3, 0x9C, 0x1E, 0x5E, 0xF1, 0x30,
  0xE6, 0x00, 0x3F, 0x13, 0xA0, 0x7A, 0xB6, 0x02, 0x86, 0x4D, 0xC2, 0x70, 0x19, 0x1F, 0xD1, 0xD9,
  0x8E, 0x0B, 0x64, 0x4A, 0xF2, 0xC6, 0xEB, 0xB5, 0x1C, 0x14, 0x6C, 0xC0, 0x54, 0xD3, 0x69, 0x5C,
  0x00, 0xB1, 0xA8, 0x7F, 0xA2, 0x91, 0xAD, 0x8E, 0x08, 0xF6, 0xC9, 0x03, 0x71, 0xA9, 0x74, 0x64,
  0x66, 0xDE, 0x4E, 0x02, 0x08, 0x35, 0x39, 0x40, 0x9C, 0x75, 0x10, 0x0D, 0x9D, 0x61, 0x7F, 0x63,
};

const unsigned char hiddenKeys_RB4[384] = {
  0x4C, 0x22, 0xD9, 0x28, 0xA6, 0x23, 0x01, 0x62, 0x0A, 0x84, 0x86, 0x27, 0xBB, 0xCC, 0x88, 0x9E,
  0x33, 0x3A, 0x6B, 0x23, 0x92, 0x22, 0xA2, 0xB4, 0x81, 0x64, 0x4E, 0x8D, 0x25, 0x69, 0x9F, 0xDC,
  0x64, 0xF1, 0x5F, 0x54, 0xCA, 0x70, 0xB8, 0x8B, 0xF8, 0xAA, 0x2A, 0xD3, 0xD9, 0xEC, 0x3B, 0x49,
  0xE8, 0x0A, 0x3E, 0xE3, 0x46, 0xB1, 0xBF, 0x27, 0x1B, 0x6C, 0x76, 0x11, 0xC8, 0x35, 0x7A, 0xB4,
  0x74, 0xF7, 0x42, 0xA5, 0xF1, 0xC7, 0x56, 0x2D, 0x31, 0xE1, 0x73, 0xF9, 0x96, 0x93, 0x89, 0x85,
  0xA7, 0xAC, 0x34, 0x46, 0x68, 0xD0, 0xBD, 0x6E, 0x08, 0xFF, 0x5E, 0x8A, 0xAE, 0x93, 0xA2, 0xDB,
  0xF8, 0xA3, 0x21, 0x5C, 0xC2, 0xBF, 0xC1, 0xC0, 0xAF, 0x79, 0x1D, 0x96, 0x43, 0x43, 0xD5, 0xF9,
  0x8F, 0xD9, 0xC8, 0xC9, 0xCE, 0x6E, 0x68, 0x93, 0x32, 0x5C, 0x80, 0xFA, 0x18, 0xE4, 0x3A, 0x06,
  0x8D, 0x99, 0x57, 0xB0, 0x0D, 0xE0, 0x26, 0xDC, 0xDA, 0xD3, 0xDA, 0x2B, 0x03, 0x74, 0x35, 0xC3,
  0xFA, 0x23, 0x4E, 0x96, 0x62, 0xEA, 0xF0, 0xD4, 0xC6, 0xC7, 0x7F, 0x6E, 0xBA, 0xA9, 0x42, 0x7D,
  0xB1, 0x70, 0x75, 0x8C, 0x92, 0x76, 0xB6, 0x3C, 0xFB, 0x72, 0x78, 0x7C, 0x19, 0x5E, 0x31, 0xA5,
  0x0C, 0x6A, 0x1E, 0x24, 0x79, 0x51, 0x85, 0xA0, 0x53, 0xE4, 0x3E, 0xC2, 0x86, 0x15, 0x25, 0xBA,
  0x19, 0xB1, 0xBC, 0x30, 0x61, 0x7E, 0x84, 0x06, 0x34, 0xB9, 0x81, 0xA9, 0x5D, 0xD3, 0x4C, 0x86,
  0x2B, 0xB1, 0xD4, 0xA9, 0xF0, 0x21, 0xFB, 0x61, 0xFE, 0x8B, 0x26, 0x83, 0x92, 0x20, 0xE6, 0xBC,
  0x49, 0x1A, 0xBD, 0xC3, 0xDB, 0x75, 0x30, 0x22, 0x84, 0x11, 0xC8, 0x1C, 0x33, 0xE8, 0x4D, 0x5A,
  0x34, 0x79, 0xC3, 0x9F, 0xED, 0x8F, 0x81, 0xF6, 0xB3, 0xA5, 0xE8, 0xE1, 0x04, 0xEE, 0x3A, 0xF0,
  0x44, 0xB1, 0x0A, 0x9F, 0x80, 0x9A, 0xB0, 0x20, 0x4C, 0x16, 0xC7, 0x9C, 0xC9, 0x78, 0x84, 0xA9,
  0x92, 0xC7, 0xEA, 0x53, 0x81, 0x4E, 0xC3, 0xCC, 0x2F, 0x0B, 0x0C, 0x86, 0xE0, 0x8D, 0xA5, 0x02,
  0xDF, 0x64, 0x2A, 0x87, 0xCB, 0xA7, 0x22, 0xD5, 0xFF, 0x9C, 0x8D, 0x58, 0xC9, 0x89, 0x35, 0x38,
  0x79, 0xA4, 0x09, 0xC8, 0x2E, 0xE8, 0xB5, 0x90, 0x8A, 0xE9, 0xD3, 0xA3, 0x2D, 0x49, 0x71, 0x9C,
  0x04, 0xEC, 0xC2, 0x82, 0x0E, 0x61, 0xAB, 0xB3, 0x4B, 0x4C, 0x6C, 0x10, 0xE5, 0xFA, 0x8F, 0xC7,
  0xDD, 0xA5, 0x45, 0x16, 0x5C, 0x37, 0xCF, 0x70, 0xE9, 0xFE, 0x5D, 0x9B, 0xE6, 0xB2, 0xA5, 0x85,
  0xB3, 0xCC, 0x1C, 0xAA, 0x9A, 0x16, 0x32, 0xE7, 0x0C, 0x41, 0xC0, 0xBD, 0x70, 0x1E, 0xBC, 0x72,
  0x17, 0xCB, 0x04, 0x6B, 0x14, 0x00, 0x13, 0xB6, 0x37, 0x33, 0xA3, 0xB7, 0xD3, 0xDD, 0xC9, 0x1A
};

const unsigned char hiddenKeys_FUSER[384] = {
  0xfe, 0x0e, 0x46, 0xa5, 0x59, 0x14, 0x7c, 0x30, 0xb4, 0x6a, 0x42, 0xcb, 0x75, 0x71, 0xbb, 0xcd,
  0xd8, 0xc3, 0x20, 0xdc, 0x2e, 0xf7, 0x02, 0x8b, 0x03, 0x36, 0x43, 0x96, 0xaf, 0xde, 0x2d, 0x71,
  0xaf, 0xa3, 0xf3, 0x3b, 0xdb, 0x8f, 0xe2, 0xf5, 0x96, 0x45, 0x8a, 0x37, 0xed, 0xb9, 0xab, 0x18,
  0x1f, 0xb2, 0xdd, 0x75, 0xa6, 0x2a, 0x66, 0xe6, 0xc4, 0xc1, 0x44, 0xf4, 0x78, 0x15, 0x9f, 0x38,
  0xe9, 0x61, 0x9c, 0x1c, 0x51, 0x16, 0x49, 0x77, 0xb3, 0xe3, 0xc5, 0xf9, 0x57, 0x73, 0x78, 0xee,
  0x72, 0xa5, 0x11, 0x24, 0x0e, 0xd6, 0x71, 0x85, 0xf1, 0xb7, 0xd7, 0x09, 0x0a, 0x95, 0x04, 0x82,
  0xb5, 0x82, 0x8b, 0xc7, 0x2b, 0x0b, 0xe8, 0x45, 0x23, 0x5a, 0xe7, 0xb4, 0xe4, 0x32, 0x59, 0x82,
  0xb0, 0x89, 0x2f, 0xc8, 0x0f, 0x53, 0xbd, 0x1c, 0xda, 0x9b, 0x8e, 0x28, 0x6f, 0x0f, 0x7e, 0xf0,
  0x54, 0x1d, 0x9e, 0xbc, 0x51, 0xdf, 0x27, 0x95, 0xa4, 0x3f, 0xcc, 0xcb, 0xb4, 0x1c, 0x3d, 0x60,
  0x15, 0xef, 0x5d, 0x3e, 0x46, 0x3d, 0x2b, 0x17, 0x98, 0x97, 0x89, 0xa0, 0x7f, 0xf1, 0x59, 0xa3,
  0xf2, 0xe9, 0xb4, 0x72, 0xf2, 0x65, 0x22, 0xa3, 0x38, 0x1a, 0xdd, 0xe3, 0x83, 0xed, 0x95, 0xd1,
  0x6e, 0xcf, 0xc6, 0xeb, 0x87, 0x63, 0x4f, 0x71, 0x85, 0xa9, 0x15, 0x62, 0x43, 0x6c, 0x18, 0x98,
  0x25, 0x8b, 0xfa, 0xf6, 0xfc, 0x92, 0x38, 0x9e, 0xbf, 0x53, 0x45, 0x33, 0xab, 0x9c, 0xcd, 0x53,
  0x41, 0x79, 0xc3, 0x27, 0x50, 0xbc, 0xd2, 0x47, 0x3a, 0x49, 0x39, 0xf9, 0x87, 0x54, 0x8f, 0xfe,
  0x29, 0x5a, 0xea, 0xba, 0x0a, 0xef, 0x1f, 0xcd, 0x22, 0x1e, 0x48, 0x3e, 0x70, 0xf0, 0x62, 0x21,
  0x8c, 0x83, 0xf6, 0x8a, 0x10, 0x3b, 0x55, 0x6e, 0xb5, 0x35, 0xbb, 0x70, 0x4f, 0xec, 0xa1, 0xfb,
  0x08, 0x2c, 0x3a, 0xec, 0x3f, 0xfa, 0x71, 0xb7, 0x25, 0x3c, 0x4b, 0xfc, 0xe5, 0x5c, 0xaf, 0x6b,
  0x31, 0x43, 0x05, 0x73, 0x99, 0xb3, 0x56, 0xf7, 0xcd, 0xe5, 0x44, 0x81, 0x81, 0x97, 0xba, 0xd9,
  0x03, 0x4d, 0xd2, 0xf2, 0x44, 0xb6, 0x8f, 0xa2, 0x94, 0xfd, 0x8d, 0x0b, 0x22, 0x97, 0x91, 0x50,
  0xb4, 0xaf, 0x5a, 0xd2, 0x92, 0x94, 0x6b, 0xa3, 0x55, 0x56, 0xa8, 0xe5, 0x3f, 0x5c, 0xdd, 0x4f,
  0x81, 0x84, 0x19, 0x91, 0x45, 0x40, 0x3f, 0x9d, 0x7c, 0x47, 0xf4, 0x5d, 0x57, 0x56, 0x80, 0x30,
  0xd9, 0x98, 0x1c, 0x65, 0x5e, 0x07, 0xce, 0x9d, 0xd1, 0x20, 0x62, 0x9d, 0x45, 0x8f, 0xbb, 0x0c,
  0xb5, 0xa2, 0x15, 0x9d, 0x15, 0x86, 0x9f, 0x6e, 0x80, 0x55, 0x8c, 0xe6, 0x6c, 0x68, 0x71, 0xee,
  0x7e, 0xed, 0x19, 0x9c, 0xb0, 0x80, 0xc5, 0x5f, 0xdc, 0x9f, 0xd1, 0x4a, 0x01, 0x36, 0xf4, 0x39
};

#endif // ndef RB1