// leave this in cmake_modules/; it makes bootstrapping easier
// since Maud.cmake assumes that test_* are next to it.
module;
#include <gmock/gmock-matchers.h>
#include <gtest/gtest.h>

#include <any>
#include <coroutine>
#include <cstdint>
#include <exception>
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

std::vector<std::any> parameters;

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

  void register_range(Info info, auto &&range) {
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
    parameters.emplace_back(std::move(vector));
  }

  void register_(Info info, auto &&parameters) {
    if constexpr (std::is_invocable_v<decltype(parameters)>) {
      register_range(info, std::move(parameters)());
    } else {
      register_range(info, std::move(parameters));
    }
  }

  template <typename T>
  void register_(Info info, std::initializer_list<T> parameters) {
    register_range(info, parameters);
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
    parameters.emplace_back(std::move(tuple));
    std::apply(
        [&, i = 0](auto const &...parameters) mutable {
          (register_one(info, &parameters, i++, type_name<T>), ...);
        },
        std::any_cast<decltype(tuple) const &>(parameters.back()));
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
  s += "Expected: ";
  int negation = e.condition_string.starts_with("not ") ? 4
               : e.condition_string.starts_with("!")    ? 1
                                                        : 0;
  s += e.condition_string.substr(negation);
  if constexpr (not std::is_same_v<C, bool>) {
    s += " (";
    s += testing::PrintToString(c.condition);
    s += ")";
  }
  s += "\n    to be ";
  s += (negation ? "false" : "true");
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

  auto lhs = testing::PrintToString(c.lhs);
  auto i = e.condition_string.find(c.name);
  //__________
  // www == www
  // w == w
  //
  // www == www
  //..w == w
  //__________
  // w == w
  // www == www
  //
  //..w == w
  // www == www
  //__________
  // wwwwwwwwww
  // w == w
  // wwwww == w
  //
  // wwwwwwwwww
  // w ....== w
  // wwwww == w
  int offset = 0;
  if (i != std::string_view::npos) {
    offset = int(i) - lhs.size() - 1;
  }
  std::string s;
  s += "Expected: ";
  if (offset < 0) {
    s += std::string(-offset, ' ');
  }
  s += e.condition_string;
  s += "\n";
  s += "  Actual: ";
  if (offset > 0) {
    s += std::string(offset, ' ');
  }
  s += testing::PrintToString(c.lhs);
  s += " vs ";
  s += testing::PrintToString(c.rhs);
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
  auto cs = e.condition_string;
  cs = cs.substr(cs.find_first_not_of(" \n\t\r"));
  cs = cs.substr(0, cs.find(">>="));
  std::stringstream stream;
  stream << "  Expected: " << cs;
  ::testing::internal::StreamMatchResultListener listener{&stream};
  if (matcher.MatchAndExplain(condition, &listener)) return {};
  stream << " ";
  matcher.DescribeTo(&stream);
  stream << "\n  Argument was: " << PrintToString(condition);
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
