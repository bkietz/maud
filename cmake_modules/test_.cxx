// leave this in cmake_modules/; it makes bootstrapping easier
// since Maud.cmake assumes that test_* are next to it.
module;
#include <gmock/gmock-matchers.h>
#include <gtest/gtest.h>

#include <any>
#include <span>
#include <sstream>
#include <vector>
export module test_;
export import :main;

using namespace testing;

///.. cpp:var:: template <typename T> std::string const type_name
///
/// A string representation of a type's name.
///
/// By default this is a best effort demangling from type_info.
/// This template can be specialized to override the default string.
///
/// .. code-block::
///
///   template <>
///   std::string const type_name<Set<int>> = "Selection";
export template <typename T>
std::string const type_name = testing::internal::GetTypeName<T>();

export using testing::PrintToString;

export template <>
std::string const type_name<std::string> = "std::string";

export template <>
std::string const type_name<std::string_view> = "std::string_view";

export struct Main {
  Main(int &argc, char **argv) { InitGoogleTest(&argc, argv); }
  int run() { return RUN_ALL_TESTS(); }
};

template <typename R>
concept SizedRange = requires(R range) {
  { range.size() } -> std::same_as<std::size_t>;
};

std::vector<std::any> parameter_keepalives;

struct Info {
  char const *file;
  int line;
  char const *test_name;
};

export template <typename Case>
struct Registrar {
  template <typename Parameter>
  void register_one(Info info, Parameter const *parameter, int i = -1,
                    std::string type_name = "") {
    constexpr bool HAS_PARAMETER = not std::is_same_v<Parameter, std::nullptr_t>;

    auto [file, line, test_name] = info;

    std::string suite_name{file};
    if (auto i = suite_name.find_last_of("\\/"); i != std::string::npos) {
      suite_name = suite_name.substr(i + 1);
    }
    if (auto i = suite_name.find_first_of('.'); i != std::string::npos) {
      suite_name = suite_name.substr(0, i);
    }

    char const *type_param = nullptr;
    char const *value_param = nullptr;

    std::string name = test_name;
    if (i != -1) {
      name += "/" + PrintToString(i);
    }
    if (not type_name.empty()) {
      // type_param = type_name.c_str();
      name += "/" + type_name;
    }
    if constexpr (HAS_PARAMETER) {
      auto old_size = name.size();
      name += "/" + PrintToString(*parameter);
      // value_param = name.c_str() + old_size + 1;
    }

    struct Fixture : testing::Test {
      void TestBody() override { Case::body(*_parameter); }
      explicit Fixture(Parameter const *p) : _parameter{p} {}
      Parameter const *_parameter;
    };

    testing::RegisterTest(
        suite_name.c_str(), name.c_str(), type_param, value_param, file, line,
        [parameter]() -> testing::Test * { return new Fixture{parameter}; });
  }

  void register_(Info info, auto &&range) {
    std::vector<std::decay_t<decltype(*range.begin())>> vector;
    if constexpr (SizedRange<decltype(range)>) {
      vector.reserve(range.size());
    }
    for (auto &&parameter : range) {
      vector.push_back(std::move(parameter));
    }
    for (int i = 0; auto const &parameter : vector) {
      register_one(info, &parameter, i++);
    }
    parameter_keepalives.emplace_back(std::move(vector));
  }

  template <typename T>
  void register_(Info info, std::initializer_list<T> initializer_list) {
    register_(info, std::span{initializer_list});
  }

  void register_(Info info, auto &&...parameters)
    requires(sizeof...(parameters) != 1)
  {
    if constexpr (sizeof...(parameters) == 0) {
      constexpr auto NULLPTR = nullptr;
      register_one(info, &NULLPTR);
    } else {
      register_(info, std::tuple{std::move(parameters)...});
    }
  }

  template <typename... T>
  void register_(Info info, std::tuple<T...> tuple) {
    parameter_keepalives.emplace_back(std::move(tuple));
    std::apply(
        [&, i = 0](auto const &...parameters) mutable {
          (register_one(info, &parameters, i++, type_name<T>), ...);
        },
        std::any_cast<decltype(tuple) const &>(parameter_keepalives.back()));
  }
};

namespace expect_helper {

export struct Begin {};
export struct End {
  std::string_view condition_string;
};

export struct Expectation {
  char const *file;
  int line;
  std::string failure;

  [[maybe_unused]] static Expectation &&maybe_unused(Expectation &&e) {
    return std::move(e);
  }

  operator bool() const { return failure.empty(); }

  template <std::invocable<std::ostream &> C>
  Expectation &&operator or(C on_fail) && {
    if (not failure.empty()) {
      std::stringstream ss{std::move(failure)};
      on_fail(ss);
      failure = std::move(ss).str();
    }
    return std::move(*this);
  }

  ~Expectation() {
    if (*this) return;
    GTEST_MESSAGE_AT_(file, line, failure.c_str(),
                      ::testing::TestPartResult::kNonFatalFailure);
  }
};

auto split_condition_string(std::string_view condition_string, std::string_view op) {
  struct Pair {
    std::string_view lhs, rhs;
  };
  auto lhs = condition_string.substr(0, condition_string.find(op));
  auto rhs = condition_string.substr(lhs.size() + op.size());
  if (rhs.find(op) == rhs.npos) {
    lhs = lhs.substr(0, lhs.find_last_of(' '));
    rhs = rhs.substr(rhs.find_first_not_of(' '));
    return Pair{lhs, rhs};
  }
  // If there is more than one instance of op in the condition string,
  // it's ambiguous where the LHS and RHS lie. We'd have to parse
  // condition_string as a C++ expression, which is way too much
  // work for such edge cases as `EXPECT_(x_eq_y == (x == y)`
  //
  // We make a last-ditch effort to split correctly by excluding copies
  // of op which lie in a string literal or parenthesis.
  std::string open_chars = R"([{("')}])";
  open_chars.append({op[0]});
  char const *candidate = nullptr;
  auto c = condition_string;
  int depth = 0;

  for (size_t i = c.find_first_of(open_chars); i != c.npos;
       i = c.find_first_of(open_chars)) {
    c = c.substr(i);
    switch (c[0]) {
      case '\'':
      case '"':
        if (c.data()[-1] == 'R') {
          auto end_tag = ")" + std::string{c.substr(1, c.find_first_of('('))} + "\"";
          c = c.substr(c.find(end_tag) + end_tag.size());
        } else {
          char end = c[0];
          c = c.substr(1);
          for (;;) {
            c = c.substr(c.find_first_of(std::string{end, '\\'}));
            if (c[0] == end) break;
            c = c.substr(2);
          }
          c = c.substr(1);
        }
        continue;

      case '(':
      case '{':
      case '[':
        c = c.substr(1);
        ++depth;
        continue;

      case ']':
      case '}':
      case ')':
        c = c.substr(1);
        --depth;
        continue;

      default:  // op[0]
        if (depth > 0 or not c.starts_with(op)) {
          c = c.substr(c.find_first_not_of("<=>"));
          continue;
        }
        c = c.substr(op.size());

        if (c[0] == '<' or c[0] == '=' or c[0] == '>') {
          c = c.substr(1);
          continue;
        }

        if (not candidate) {
          // Store the candidate and continue searching
          candidate = c.data() - op.size();
          continue;
        }

        // This is the *second* candidate we've found so far,
        // we won't be able to decide between them; just bail.
        return Pair{};
    }
  }
  // candidate points to the start of the single significant
  // instance of op in condition_string
  lhs = condition_string.substr(0, candidate - condition_string.data());
  rhs = condition_string.substr(lhs.size() + op.size());

  lhs = lhs.substr(0, lhs.find_last_of(' '));
  rhs = rhs.substr(rhs.find_first_not_of(' '));
  return Pair{lhs, rhs};
}

export template <typename C>
struct Condition {
  C const &condition;
};
export template <typename C>
Condition<C> operator<=(Begin, C const &condition) {
  return {condition};
}
export template <typename C>
std::string operator,(Condition<C> c, End e) {
  if (c.condition) return {};

  std::string s;
  auto cs = e.condition_string;
  bool negated = false;
  if (cs.starts_with("!")) {
    cs = cs.substr(1);
    negated = true;
  } else if (cs.starts_with("not ")) {
    cs = cs.substr(4);
    negated = true;
  } else if (cs.starts_with("not")) {
    bool is_ident = cs[3] >= 'a' and cs[3] <= 'z' or cs[3] >= 'A' and cs[3] <= 'Z'
                 or cs[3] >= '0' and cs[3] <= '9' or cs[3] == '_';
    if (not is_ident) {
      cs = cs.substr(3);
      negated = true;
    }
  }
  s += "Expected ";
  s += (negated ? "falsy: " : "truthy: ");
  s += cs;
  if constexpr (not std::is_same_v<C, bool>) {
    if (not negated) {
      s += "\n(it was ";
      s += testing::PrintToString(c.condition);
      s += ")";
    }
  }
  return s;
}

export template <typename L, typename R>
struct Comparison {
  L const &lhs;
  R const &rhs;
  bool condition;
  std::string_view name;
};
export template <typename L, typename R>
Comparison<L, R> operator==(Condition<L> lhs, R const &rhs) {
  return {lhs.condition, rhs, lhs.condition == rhs, "=="};
}
export template <typename L, typename R>
Comparison<L, R> operator!=(Condition<L> lhs, R const &rhs) {
  return {lhs.condition, rhs, lhs.condition != rhs, "!="};
}
export template <typename L, typename R>
Comparison<L, R> operator>(Condition<L> lhs, R const &rhs) {
  return {lhs.condition, rhs, lhs.condition > rhs, ">"};
}
export template <typename L, typename R>
Comparison<L, R> operator>=(Condition<L> lhs, R const &rhs) {
  return {lhs.condition, rhs, lhs.condition >= rhs, ">="};
}
export template <typename L, typename R>
Comparison<L, R> operator<(Condition<L> lhs, R const &rhs) {
  return {lhs.condition, rhs, lhs.condition < rhs, "<"};
}
export template <typename L, typename R>
Comparison<L, R> operator<=(Condition<L> lhs, R const &rhs) {
  return {lhs.condition, rhs, lhs.condition <= rhs, "<="};
}
export template <typename L, typename R>
std::string operator,(Comparison<L, R> c, End e) {
  if (c.condition) return {};

  std::string s;

  auto [lhs_expected, rhs_expected] = split_condition_string(e.condition_string, c.name);
  auto lhs_actual = testing::PrintToString(c.lhs);
  auto rhs_actual = testing::PrintToString(c.rhs);
  // TODO add a diff if both {lhs,rhs}_actual are multiline

  if (lhs_expected.empty()) {
    // Can't split the condition_string into LHS,RHS so
    // fall back to no indentation.
    s = "Expected: " + std::string{e.condition_string} + "\n";
    s += "  Actual:"
       + (lhs_actual.size() + rhs_actual.size() < 80
              ? " " + lhs_actual + " vs " + rhs_actual
              : "\n" + lhs_actual + "\n    vs\n" + rhs_actual);
    return s;
  }

  auto op = " " + std::string{c.name} + " ";

  auto lhs_size = std::max(lhs_expected.size(), lhs_actual.size());
  auto rhs_size = std::max(rhs_expected.size(), rhs_actual.size());
  if (lhs_size + rhs_size < 80) {
    std::string offset_actual(lhs_size - lhs_actual.size(), ' ');
    std::string offset_expected(lhs_size - lhs_expected.size(), ' ');
    s += "Expected: " + offset_expected;
    s += lhs_expected;
    s += op;
    s += rhs_expected;
    s += "\n";
    s += "  Actual: " + offset_actual;
    s += lhs_actual + " vs " + rhs_actual;
    return s;
  }

  if (lhs_actual.size() + rhs_size < 80) {
    s += "Expected: ";
    s += lhs_expected;
    s += "\n";
    s.append(sizeof("  Actual:") + lhs_actual.size(), ' ');
    s += op;
    s += rhs_expected;
    s += "\n";
    s += "  Actual: ";
    s += lhs_actual + " vs " + rhs_actual;
    return s;
  }

  s += "Expected:"
     + (lhs_expected.size() + rhs_expected.size() < 80
            ? " " + std::string{lhs_expected} + op + std::string{rhs_expected} + "\n"
            : "\n" + std::string{lhs_expected} + "\n   " + op + "\n"
                  + std::string{rhs_expected} + "\n\n");
  s += "  Actual:"
     + (lhs_actual.size() + rhs_actual.size() < 80
            ? " " + lhs_actual + " vs " + rhs_actual
            : "\n" + lhs_actual + "\n    vs\n" + rhs_actual);
  return s;
}

template <typename C>
struct MatchCondition {
  C const &condition;
  testing::Matcher<C const &> matcher;
};
export template <typename C, typename M>
MatchCondition<C> operator>>=(Condition<C> c, M matcher) {
  return {c.condition, SafeMatcherCast<C const &>(std::move(matcher))};
}
export template <typename C>
std::string operator,(MatchCondition<C> c, End e) {
  auto &[condition, matcher] = c;
  std::stringstream stream;
  ::testing::internal::StreamMatchResultListener listener{&stream};
  if (matcher.MatchAndExplain(condition, &listener)) return {};

  auto [condition_string, _] = split_condition_string(e.condition_string, ">>=");
  stream << "Expected: " << condition_string << " ";
  matcher.DescribeTo(&stream);
  stream << "\nArgument: " << PrintToString(condition);
  return std::move(stream).str();
}

}  // namespace expect_helper

export using testing::internal::AnythingMatcher;

export using testing::A;
export using testing::An;

export using testing::Eq;
export using testing::Ge;
export using testing::Gt;
export using testing::Le;
export using testing::Lt;
export using testing::Ne;
// export using testing::IsFalse;
// export using testing::IsTrue;
export using testing::IsNull;
export using testing::NotNull;
export using testing::Optional;
export using testing::VariantWith;
export using testing::Ref;
export using testing::TypedEq;

export using testing::DoubleEq;
export using testing::FloatEq;
export using testing::NanSensitiveDoubleEq;
export using testing::NanSensitiveFloatEq;
export using testing::IsNan;
export using testing::DoubleNear;
export using testing::FloatNear;
export using testing::NanSensitiveDoubleNear;
export using testing::NanSensitiveFloatNear;

export using testing::ContainsRegex;
export using testing::EndsWith;
export using testing::HasSubstr;
// export using testing::IsEmpty;
export using testing::MatchesRegex;
export using testing::StartsWith;
export using testing::StrCaseEq;
export using testing::StrCaseNe;
export using testing::StrEq;
export using testing::StrNe;
export using testing::WhenBase64Unescaped;

export using testing::BeginEndDistanceIs;
export using testing::ContainerEq;
export using testing::Contains;
export using testing::Each;
export using testing::ElementsAre;
export using testing::ElementsAreArray;
// export using testing::IsEmpty;
export using testing::IsSubsetOf;
export using testing::IsSupersetOf;
export using testing::Pointwise;
export using testing::SizeIs;
export using testing::UnorderedElementsAre;
export using testing::UnorderedElementsAreArray;
export using testing::UnorderedPointwise;
export using testing::WhenSorted;
export using testing::WhenSortedBy;

export using testing::Field;
export using testing::Key;
export using testing::Pair;
export using testing::FieldsAre;
export using testing::Property;

export using testing::ResultOf;
export using testing::AllArgs;
export using testing::Args;

export using testing::Address;
export using testing::Pointee;
export using testing::Pointer;
export using testing::WhenDynamicCastTo;

export using testing::AllOf;
export using testing::AllOfArray;
export using testing::AnyOf;
export using testing::AnyOfArray;
export using testing::Not;
export using testing::Conditional;

export using testing::DescribeMatcher;

export template <typename T, typename M>
bool ExplainMatchResult(M matcher, T const &value, std::ostream &os) {
  testing::internal::StreamMatchResultListener listener{&os};
  return testing::SafeMatcherCast<T const &>(matcher).MatchAndExplain(value, &listener);
}

template <typename Match>
struct DefaultDescription {
  void operator()(std::ostream &os, bool negated) const {
    os << (negated ? "not (" : "(") << type_name<Match> << ")";
  }
};

///.. cpp:struct:: Matcher
///
/// Helper for constructing matchers from lambdas.
///
/// Matchers can be used with :c:macro:`EXPECT_` using ``operator>>=``.
///
/// For example, to define a matcher which checks whether a number is even:
///
/// .. code-block::
///
///   Matcher IsEven = [](auto n, std::ostream &os) {
///     return (n % 2) == 0;
///   };
///
/// To parameterize a matcher, define a function which returns a matcher
/// with the parameters in closure:
///
/// .. code-block::
///
///   auto IsDivisibleBy(auto divisor) {
///     return Matcher{[=](auto n, std::ostream &os) {
///       os << "where the remainder is " << (n % divisor);
///       return (n % divisor) == 0;
///     }};
///   }
///
/// On failed expectations, matchers output a description of the way
/// matching failed. By default, this uses the :var:`type_name\<T>` of
/// the match lambda (which is usually something unique but uninformative,
/// like ``"$_1"``).
/// Description of the matcher can be customized with another lambda:
///
/// .. code-block::
///
///   auto BarPlusBazEq(int n) {
///     return Matcher{
///       .match = [=](Foo f, std::ostream &os) { return f.bar() + f.baz() == n; },
///       .description = [=](std::ostream &os, bool negated) {
///         os << "bar() + baz()";
///         os << (negated ? " does not equal " : " equals ") << n;
///       },
///     };
///   }
///
/// Frequently, a lambda is sufficient for constructing a custom matcher.
/// However, it's worth noting that defining a
/// :gtest:`custom matcher class <gmock_cook_book.html#CustomMatcherClass>`
/// is not prohibitively complex.
export template <typename Match, typename Description = DefaultDescription<Match>>
struct Matcher {
  Match match;
  Description description;
  using is_gtest_matcher = void;
  bool MatchAndExplain(auto const &x, std::ostream *os) const { return match(x, *os); }
  void DescribeTo(std::ostream *os) const { description(*os, false); }
  void DescribeNegationTo(std::ostream *os) const { description(*os, true); }
};

template <typename M>
constexpr bool is_gtest_matcher =
    requires(M const matcher) { typename M::is_gtest_matcher; };
// Annoyingly, some matchers from gmock don't
// flag themselves for easy metaprogramming. Specialize
// for them explicitly.
template <typename M>
constexpr bool is_gtest_matcher<testing::PolymorphicMatcher<M>> = true;

/// Creates a matcher that matches any value that m doesn't match.
export template <typename M>
  requires is_gtest_matcher<M>
auto operator not(M m) {
  return Not(std::move(m));
}

// TODO fold into a single AllOf/AnyOf matcher for
// con/disjunctions with more than two members

/// Creates a matcher that matches only if both argument matchers do.
export template <typename L, typename R>
  requires(is_gtest_matcher<L> and is_gtest_matcher<R>)
auto operator and(L left, R right) {
  return AllOf(std::move(left), std::move(right));
}

/// Creates a matcher that matches only if both argument matchers do.
export template <typename L, typename R>
  requires(is_gtest_matcher<L> and is_gtest_matcher<R>)
auto operator or(L left, R right) {
  return AnyOf(std::move(left), std::move(right));
}

export auto operator""_r(char const *re, size_t) { return ContainsRegex(re); }
