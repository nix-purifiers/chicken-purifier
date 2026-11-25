#include <assert.h>
#include "embedded.h"
int main(void) {
  assert(purifier_initialize() == 1);
  for (int i = 0; i < 100; ++i) assert(purifier_answer(i) == i + EXPECTED);
  return 0;
}
