#include <gtest/gtest-spi.h>

#include <cstdint>
import test_;

int a = 1, b = 2, c = 3;
uint64_t zero64 = 0;

TEST_(truthiness) {
  EXPECT_(a + b + c);

  EXPECT_NONFATAL_FAILURE(EXPECT_(bool{}), "Expected truthy: bool{}");

  EXPECT_NONFATAL_FAILURE(EXPECT_(c - c),
                          "Expected truthy: c - c\n"
                          "(it was 0)\n");
}

TEST_(falsiness) {
  EXPECT_(not 0);

  EXPECT_NONFATAL_FAILURE(EXPECT_(not a), "Expected falsy: a\n");
  EXPECT_NONFATAL_FAILURE(EXPECT_(not(a)), "Expected falsy: (a)\n");

  EXPECT_NONFATAL_FAILURE(EXPECT_(!a), "Expected falsy: a\n");
  EXPECT_NONFATAL_FAILURE(EXPECT_(!(a)), "Expected falsy: (a)\n");

  // check to make sure we don't see "Expected falsy: _a"
  bool not_a = not a;
  EXPECT_NONFATAL_FAILURE(EXPECT_(not_a), "Expected truthy: not_a\n");
}

TEST_(equality_comparison) {
  EXPECT_(a + b == c);
  EXPECT_NONFATAL_FAILURE(EXPECT_(a + a == c),
                          "Expected: a + a == c\n"
                          "  Actual:     2 vs 3");
}

TEST_(inequality_comparison) {
  EXPECT_(b + b != c);
  EXPECT_NONFATAL_FAILURE(EXPECT_(a + b != c),
                          "Expected: a + b != c\n"
                          "  Actual:     3 vs 3");
}

TEST_(less_comparison) {
  EXPECT_(a + a < c);
  EXPECT_NONFATAL_FAILURE(EXPECT_(b + c < a),
                          "Expected: b + c < a\n"
                          "  Actual:     5 vs 1");
}

TEST_(less_equal_comparison) {
  EXPECT_(a + a <= c);
  EXPECT_NONFATAL_FAILURE(EXPECT_(b + c <= a),
                          "Expected: b + c <= a\n"
                          "  Actual:     5 vs 1");
}

TEST_(greater_comparison) {
  EXPECT_(c + b > a);
  EXPECT_NONFATAL_FAILURE(EXPECT_(a + a > c),
                          "Expected: a + a > c\n"
                          "  Actual:     2 vs 3");
}

TEST_(greater_equal_comparison) {
  EXPECT_(c + b >= a);
  EXPECT_NONFATAL_FAILURE(EXPECT_(a + a >= c),
                          "Expected: a + a >= c\n"
                          "  Actual:     2 vs 3");
}

TEST_(short_lhs_indentation) {
  EXPECT_NONFATAL_FAILURE(EXPECT_(1 + 1 + 1 + 1 + 1 + 1 + 1 == 0),
                          "Expected: 1 + 1 + 1 + 1 + 1 + 1 + 1 == 0\n"
                          "  Actual:                         7 vs 0");
  EXPECT_NONFATAL_FAILURE(EXPECT_(~zero64 == 0),
                          "Expected:              ~zero64 == 0\n"
                          "  Actual: 18446744073709551615 vs 0");
}

TEST_(long_expectation_lhs_puts_rhs_on_next_line) {
  EXPECT_NONFATAL_FAILURE(
      EXPECT_(1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1
                  + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1
              == 0),
      "Expected: 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +"
      " 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1\n"
      "             == 0\n"
      "  Actual: 37 vs 0");
}

TEST_(long_expectation_spreads_comparison_across_lines) {
  EXPECT_NONFATAL_FAILURE(
      EXPECT_(1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1
                  + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1
              != 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1
                     + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1),
      "Expected:\n"
      "1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1"
      " + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1\n"
      "    != \n"
      "1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1"
      " + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1\n"
      "\n"
      "  Actual: 36 vs 36");
}

TEST_(long_actual_spreads_vs_across_lines) {
#define LOREM                                                                          \
  "Lorem ipsum dolor sit amet, officia excepteur ex fugiat reprehenderit enim labore " \
  "culpa sint ad nisi Lorem pariatur mollit ex esse exercitation amet. Nisi anim "     \
  "cupidatat excepteur officia. Reprehenderit nostrud nostrud ipsum Lorem est "        \
  "aliquip amet voluptate voluptate dolor minim nulla est proident. Nostrud officia "  \
  "pariatur ut officia. Sit irure elit esse ea nulla sunt ex occaecat reprehenderit "  \
  "commodo officia dolor Lorem duis laboris cupidatat officia voluptate. Culpa "       \
  "proident adipisicing id nulla nisi laboris ex in Lorem sunt duis officia eiusmod. " \
  "Aliqua reprehenderit commodo ex non excepteur duis sunt velit enim. Voluptate "     \
  "laboris sint cupidatat ullamco ut ea consectetur et est culpa et culpa duis."
  EXPECT_NONFATAL_FAILURE(EXPECT_(LOREM == ""),
                          "Expected: LOREM == \"\"\n"
                          "  Actual:\n"
                          "\"" LOREM
                          "\""
                          "\n    vs\n\"\"");
}

TEST_(correct_indentation_even_for_op_in_literal) {
  EXPECT_("a" + std::string(" == ") + "b" == "a" + std::string(" == ") + "b");
  EXPECT_NONFATAL_FAILURE(
      EXPECT_("A" + std::string(" == ") + "B" == "a" + std::string(" == ") + "b"),
      R"(Expected: "A" + std::string(" == ") + "B" == "a" + std::string(" == ") + "b")"
      "\n"
      R"(  Actual:                        "A == B" vs "a == b")");
}

template <int I>
constexpr int INT_CONSTANT = I;

TEST_(graceful_indentation_breakage) {
  EXPECT_(INT_CONSTANT<4> > INT_CONSTANT<3>);
  EXPECT_NONFATAL_FAILURE(EXPECT_(INT_CONSTANT<4> > INT_CONSTANT<5>),
                          "Expected: INT_CONSTANT<4> > INT_CONSTANT<5>\n"
                          "  Actual: 4 vs 5");

  EXPECT_(INT_CONSTANT<2> < INT_CONSTANT<3>);
  EXPECT_NONFATAL_FAILURE(EXPECT_(INT_CONSTANT<4> < INT_CONSTANT<3>),
                          "Expected: INT_CONSTANT<4> < INT_CONSTANT<3>\n"
                          "  Actual: 4 vs 3");

  // we can recover pretty indentation by parenthesizing
  EXPECT_((INT_CONSTANT<2>) < (INT_CONSTANT<3>));
  EXPECT_NONFATAL_FAILURE(EXPECT_((INT_CONSTANT<4>) < (INT_CONSTANT<3>)),
                          "Expected: (INT_CONSTANT<4>) < (INT_CONSTANT<3>)\n"
                          "  Actual:                 4 vs 3");
}

TEST_(HasSubstr_matcher) {
  std::string fb = "foo-bar";
  EXPECT_(fb >>= HasSubstr("o-b"));
  EXPECT_NONFATAL_FAILURE(EXPECT_(fb >>= HasSubstr("===")),
                          "Expected: fb has substring \"===\"\n"
                          "Argument: \"foo-bar\"");
}

TEST_(regex_matcher) {
  std::string fb = "fff-bbbb";
  EXPECT_(fb >>= "^f+-b+$"_r);
  EXPECT_NONFATAL_FAILURE(EXPECT_(fb >>= "^b+-f+$"_r),
                          "Expected: fb contains regular expression \"^b+-f+$\"\n"
                          "Argument: \"fff-bbbb\"");
}

TEST_(negated_HasSubstr_matcher) {
  std::string fb = "foo-bar";
  EXPECT_(fb >>= not HasSubstr("==="));
  EXPECT_NONFATAL_FAILURE(EXPECT_(fb >>= not HasSubstr("o-b")),
                          "Expected: fb has no substring \"o-b\"\n"
                          "Argument: \"foo-bar\"");
}

TEST_(conjunction_of_HasSubstr_matchers) {
  std::string fb = "foo-bar";
  EXPECT_(fb >>= HasSubstr("foo") and HasSubstr("bar"));
  EXPECT_NONFATAL_FAILURE(
      EXPECT_(fb >>= HasSubstr("===") and HasSubstr("o-b")),
      "Expected: fb (has substring \"===\") and (has substring \"o-b\")\n"
      "Argument: \"foo-bar\"");
}

TEST_(disjunction_of_HasSubstr_matchers) {
  std::string fb = "foo-bar";
  EXPECT_(fb >>= HasSubstr("o-b") or HasSubstr("==="));
  EXPECT_NONFATAL_FAILURE(
      EXPECT_(fb >>= HasSubstr("===") or HasSubstr("---")),
      "Expected: fb (has substring \"===\") or (has substring \"---\")\n"
      "Argument: \"foo-bar\"");
}
