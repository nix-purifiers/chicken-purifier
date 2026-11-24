#include <chicken.h>
#include "embedded.h"

int purifier_initialize(void) {
  /* Explicit native nursery size; the SDK default can exceed a JVM thread's stack. */
  if (!CHICKEN_initialize(0, 64 * 1024, 0, C_toplevel)) return 0;
  CHICKEN_run(NULL);
  return 1;
}
