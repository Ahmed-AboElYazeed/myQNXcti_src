#pragma once
// Undefine QNX math.h macros that conflict with std::isnan etc.
// <cmath> is intentionally NOT included here — it must be included
// by the source file itself after its own include ordering is set up.
#undef isnan
#undef isinf
#undef isfinite
#undef signbit
#undef isnormal
#undef fpclassify
#undef isinf
