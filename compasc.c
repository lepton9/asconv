#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <jpeglib.h>


typedef struct pixel {
  uint32_t value;
  unsigned char a;
  unsigned char r;
  unsigned char g;
  unsigned char b;
} pixel;

uint8_t a(uint32_t pixel) {
  return ((0xFF000000&pixel)>>8*3);
}
uint8_t r(uint32_t pixel) {
  return ((0x00FF0000&pixel)>>8*2);
}
uint8_t g(uint32_t pixel) {
  return ((0x0000FF00&pixel)>>8*1);
}
uint8_t b(uint32_t pixel) {
  return ((0x000000FF&pixel)>>8*0);
}

// Compress a chunk of pixels by taking a average of the values
int compChunk() {
  return 0;
}

int pixel_intensity(uint32_t pixel) {
  return ((0xFF000000&pixel)>>8*3);
}

char convPixTochar(uint32_t pixel) {
  char table[10] = " .,:;ox%#@";
  size_t n = sizeof(table) - 1;
  int index = pixel_intensity(pixel)*n/256;
  return table[index];
}

uint32_t average() {
  return 0x00000000;
}

void setArValuesTo(uint32_t* ar, const size_t size, const uint32_t val) {
  for (int i = 0; i < size; i++) {
    ar[i] = val;
  }
}

uint32_t** mallocNullMat(const size_t h, const size_t w) {
  uint32_t** img = malloc(sizeof(uint32_t*) * h);
  for (int i = 0; i < h; i++) {
    img[i] = malloc(sizeof(uint32_t) * w);
    setArValuesTo(img[i], w, 0x00000000);
  }
  return img;
}

void freeMat(uint32_t** mat, const size_t h) {
  for (int i = 0; i < h; i++) {
    free(mat[i]);
  }
  free(mat);
}


int main() {


  int img_height = 100;
  int img_width = 100;
  uint32_t** pixels = mallocNullMat(img_height, img_width);

  for (int i = 0; i < img_height; i++) {
    for (int j = 0; j < img_height; j++) {
      printf("%d ", pixels[i][j]);
    }
    printf("\n");
  }
  
  freeMat(pixels, img_height);

  return 0;
}


