defmodule Cldr.Number.PluralRule do
  @moduledoc false

  @type operand :: any()

  defmacro __using__(opts) do
    module_name = Keyword.get(opts, :type)

    unless module_name in [:cardinal, :ordinal] do
      raise ArgumentError,
        "Invalid option #{inspect(opts)}. `type: :cardinal` or " <>
        "`type: :ordinal` are the only valid options"
    end

    quote location: :keep do
      alias Cldr.Math
      alias Cldr.LanguageTag
      alias Cldr.Locale

      import Cldr.Digits,
        only: [number_of_integer_digits: 1, remove_trailing_zeros: 1, fraction_as_integer: 2]

      import Cldr.Number.PluralRule.Compiler
      import Cldr.Number.PluralRule.Transformer

      @module Atom.to_string(unquote(module_name)) |> String.capitalize()

      @rules Cldr.Config.cldr_data_dir()
             |> Path.join("/plural_rules.json")
             |> File.read!()
             |> Cldr.Config.json_library().decode!
             |> Map.get(Atom.to_string(unquote(module_name)))
             |> Cldr.Config.normalize_plural_rules()
             |> Map.new

      @rules_locales @rules
                     |> Map.keys()
                     |> Enum.sort()

      @nplurals_range [0,1,2,3,4,5]
      @gettext_nplurals @rules
             |> Enum.map(fn {locale, rules} ->
                 {locale, Keyword.keys(rules) |> Enum.zip(@nplurals_range)}
                end)
             |> Map.new

      @config Keyword.get(unquote(opts), :config)
      @backend Map.get(@config, :backend)

      @known_locale_names @rules_locales
        |> MapSet.new()
        |> MapSet.intersection(MapSet.new(Cldr.Config.known_locale_names(@config)))
        |> MapSet.to_list()
        |> Enum.sort()

      @doc """
      The locale names for which plural rules are defined.

      """
      def available_locale_names do
        @rules_locales
      end

      @doc """
      The configured locales for which plural rules are defined.

      Returns the intersection of `#{inspect @backend}.known_locale_names/0` and
      the locales for which #{@module} plural rules are defined.

      There are many `Cldr` locales which don't have their own plural
      rules so this list is the intersection of `Cldr`'s configured
      locales and those that have rules.

      """
      @spec known_locale_names :: [Locale.locale_name(), ...]
      def known_locale_names do
        @known_locale_names
      end

      @doc """
      Returns all the plural rules defined in CLDR.

      """
      @spec plural_rules :: map()
      def plural_rules do
        @rules
      end

      @doc false
      @spec gettext_nplurals :: map()
      def gettext_nplurals do
        @gettext_nplurals
      end

      if unquote(module_name) == :cardinal do
      @doc """
      Pluralize a number using #{unquote(module_name)} plural rules
      and a substition map.

      ## Arguments

      * `number` is an integer, float or Decimal

      * `locale` is any locale returned by `#{inspect @backend}.Locale.new!/1` or any
        `locale_name` returned by `#{inspect @backend}.known_locale_names/0`

      * `substitutions` is a map that maps plural keys to a string.
        The valid substitution keys are `:zero`, `:one`, `:two`,
        `:few`, `:many` and `:other`.

      See also `#{inspect(__MODULE__)}.#{@module}.plural_rule/3`.

      ## Examples

          iex> #{inspect(__MODULE__)}.pluralize 1, "en", %{one: "one"}
          "one"

          iex> #{inspect(__MODULE__)}.pluralize 2, "en", %{one: "one"}
          nil

          iex> #{inspect(__MODULE__)}.pluralize 2, "en", %{one: "one", two: "two", other: "other"}
          "other"

          iex> #{inspect(__MODULE__)}.pluralize 22, "en", %{one: "one", two: "two", other: "other"}
          "other"

          iex> #{inspect(__MODULE__)}.pluralize Decimal.new(1), "en", %{one: "one"}
          "one"

          iex> #{inspect(__MODULE__)}.pluralize Decimal.new(2), "en", %{one: "one"}
          nil

          iex> #{inspect(__MODULE__)}.pluralize Decimal.new(2), "en", %{one: "one", two: "two"}
          nil

      """
      else
      @doc """
      Pluralize a number using #{unquote(module_name)} plural rules
      and a substition map.

      ## Arguments

      * `number` is an integer, float or Decimal

      * `locale` is any locale returned by `#{inspect @backend}.Locale.new!/1` or any
        `locale_name` returned by `#{inspect @backend}.known_locale_names/0`

      * `substitutions` is a map that maps plural keys to a string.
        The valid substitution keys are `:zero`, `:one`, `:two`,
        `:few`, `:many` and `:other`.

      See also `#{inspect(__MODULE__)}.#{@module}.plural_rule/3`.

      ## Examples

          iex> #{inspect(__MODULE__)}.pluralize 1, "en", %{one: "one"}
          "one"

          iex> #{inspect(__MODULE__)}.pluralize 2, "en", %{one: "one"}
          nil

          iex> #{inspect(__MODULE__)}.pluralize 2, "en", %{one: "one", two: "two"}
          "two"

          iex> #{inspect(__MODULE__)}.pluralize 22, "en", %{one: "one", two: "two", other: "other"}
          "two"

          iex> #{inspect(__MODULE__)}.pluralize Decimal.new(1), "en", %{one: "one"}
          "one"

          iex> #{inspect(__MODULE__)}.pluralize Decimal.new(2), "en", %{one: "one"}
          nil

          iex> #{inspect(__MODULE__)}.pluralize Decimal.new(2), "en", %{one: "one", two: "two"}
          "two"

      """
      end

      @default_substitution :other
      @spec pluralize(Math.number_or_decimal(), LanguageTag.t() | Locale.locale_name(), %{}) :: any()

      def pluralize(number, locale_name, substitutions) when is_binary(locale_name) do
        with {:ok, language_tag} <- @backend.validate_locale(locale_name) do
          pluralize(number, language_tag, substitutions)
        end
      end

      def pluralize(number, %LanguageTag{} = locale, %{} = substitutions)
          when is_number(number) do
        do_pluralize(number, locale, substitutions)
      end

      def pluralize(%Decimal{} = number, %LanguageTag{} = locale, %{} = substitutions) do
        do_pluralize(number, locale, substitutions)
      end

      defp do_pluralize(number, %LanguageTag{} = locale, %{} = substitutions) do
        plural = plural_rule(number, locale)
        substitutions[plural] || substitutions[@default_substitution]
      end

      @doc """
      Return the plural rules for a locale.

      ## Arguments

      * `locale` is any locale returned by `#{inspect @backend}.Locale.new!/1` or any
        `locale_name` returned by `#{inspect @backend}.known_locale_names/0`

      The rules are returned in AST form after parsing.

      """
      @spec plural_rules_for(Locale.locale_name() | LanguageTag.t()) :: [{atom(), list()}, ...]
      def plural_rules_for(%LanguageTag{cldr_locale_name: cldr_locale_name, language: language}) do
        plural_rules()[cldr_locale_name] || plural_rules()[language]
      end

      def plural_rules_for(locale_name) when is_binary(locale_name) do
        with {:ok, locale} <- @backend.validate_locale(locale_name) do
          plural_rules_for(locale)
        end
      end

      # Plural Operand Meanings as defined in CLDR plural rules and used
      # in the generated code
      #
      # Symbol  Value
      # n       absolute value of the source number (integer and decimals).
      # i       integer digits of n.
      # v       number of visible fraction digits in n, with trailing zeros.
      # w       number of visible fraction digits in n, without trailing zeros.
      # f       visible fractional digits in n, with trailing zeros.
      # t       visible fractional digits in n, without trailing zeros.

      if unquote(module_name) == :cardinal do
      @doc """
      Return the plural key for a given number in a given locale

      Returns which plural key (`:zero`, `:one`, `:two`, `:few`,
      `:many` or `:other`) a given number fits into within the
      context of a given locale.

      Note that these key names should not be interpreted
      literally.  For example, the key returned from
      `Cldr.Number.Ordinal.plural_rule(0, "en")` is actually
      `:other`, not `:zero`.

      This key can then be used to format a number, date, time, unit,
      list or other content in a plural-sensitive way.

      ## Arguments

      * `number` is any `integer`, `float` or `Decimal`

      * `locale` is any locale returned by `Cldr.Locale.new!/2` or any
        `locale_name` returned by `#{inspect @backend}.known_locale_names/0`

      * `rounding` is one of `#{inspect Cldr.Math.rounding_modes}`.  The
        default is `#{inspect Cldr.Math.default_rounding_mode}`.

      ## Examples

          iex> #{inspect(__MODULE__)}.plural_rule 0, "fr"
          :one

          iex> #{inspect(__MODULE__)}.plural_rule 0, "en"
          :other

      """
      else
      @doc """
      Return the plural key for a given number in a given locale

      Returns which plural key (`:zero`, `:one`, `:two`, `:few`,
      `:many` or `:other`) a given number fits into within the
      context of a given locale.

      Note that these key names should not be interpreted
      literally.  For example, the key returned from
      `Cldr.Number.Ordinal.plural_rule(0, "en")` is actually
      `:other`, not `:zero`.

      This key can then be used to format a number, date, time, unit,
      list or other content in a plural-sensitive way.

      ## Arguments

      * `number` is any `integer`, `float` or `Decimal`

      * `locale` is any locale returned by `Cldr.Locale.new!/2` or any
        `locale_name` returned by `#{inspect @backend}.known_locale_names/0`

      * `rounding` is one of `#{inspect Cldr.Math.rounding_modes}`.  The
        default is `#{inspect Cldr.Math.default_rounding_mode}`.

      ## Examples

          iex> #{inspect(__MODULE__)}.plural_rule 0, "fr"
          :other

          iex> #{inspect(__MODULE__)}.plural_rule 1, "en"
          :one

      """
      end

      @spec plural_rule(
              Math.number_or_decimal(),
              Locale.locale_name() | LanguageTag.t(),
              atom() | pos_integer()
            ) :: :zero | :one | :two | :few | :many | :other

      def plural_rule(number, locale, rounding \\ Math.default_rounding())

      def plural_rule(number, locale_name, rounding) when is_binary(locale_name) do
        with {:ok, locale} <- @backend.validate_locale(locale_name) do
          plural_rule(number, locale, rounding)
        end
      end

      def plural_rule(number, locale, rounding) when is_binary(number) do
        plural_rule(Decimal.new(number), locale, rounding)
      end

      # Plural rule for an integer
      def plural_rule(number, locale, _rounding) when is_integer(number) do
        n = abs(number)
        i = n
        v = 0
        w = 0
        f = 0
        t = 0
        do_plural_rule(locale, n, i, v, w, f, t)
      end

      # Plural rule for a float
      def plural_rule(number, locale, rounding)
          when is_float(number) and is_integer(rounding) and rounding > 0 do
        # Testing shows that this is working but just in case we
        # can go back to casting the number to a decimal and
        # using that path
        # plural_rule(Decimal.new(number), locale, rounding)
        n = Float.round(abs(number), rounding)
        i = trunc(n)
        v = rounding
        t = fraction_as_integer(n - i, rounding)
        w = number_of_integer_digits(t)
        f = trunc(t * Math.power_of_10(v - w))
        do_plural_rule(locale, n, i, v, w, f, t)
      end

      # Plural rule for a %Decimal{}
      def plural_rule(%Decimal{} = number, locale, rounding)
          when is_integer(rounding) and rounding > 0 do
        # n absolute value of the source number (integer and decimals).
        n = Decimal.abs(number)

        # i integer digits of n.
        i = Decimal.round(n, 0, :floor)

        # v number of visible fraction digits in n, with trailing zeros.
        v = abs(n.exp)

        # f visible fractional digits in n, with trailing zeros.
        f =
          n
          |> Decimal.sub(i)
          |> Decimal.mult(Decimal.new(Math.power_of_10(v)))
          |> Decimal.round(0, :floor)
          |> Decimal.to_integer()

        #   t visible fractional digits in n, without trailing zeros.
        t = remove_trailing_zeros(f)

        # w number of visible fraction digits in n, without trailing zeros.
        w = number_of_integer_digits(t)

        i = Decimal.to_integer(i)
        n = Math.to_float(n)

        do_plural_rule(locale, n, i, v, w, f, t)
      end
    end
  end

  @doc false
  def define_ordinal_and_cardinal_modules(config) do
    quote location: :keep do
      defmodule Number.Ordinal do
        @moduledoc """
        Implements ordinal plural rules for numbers.
        """

        use Cldr.Number.PluralRule, type: :ordinal, config: unquote(Macro.escape(config))
        alias Cldr.LanguageTag

        unquote(Cldr.Number.PluralRule.define_plural_rules())
      end

      defmodule Number.Cardinal do
        @moduledoc """
        Implements cardinal plural rules for numbers.
        """

        use Cldr.Number.PluralRule, type: :cardinal, config: unquote(Macro.escape(config))
        alias Cldr.LanguageTag

        unquote(Cldr.Number.PluralRule.define_plural_rules())
      end
    end
  end

  @doc false
  def define_plural_rules do
    quote bind_quoted: [], location: :keep do
      alias Cldr.Number.PluralRule
      # Generate the functions to process plural rules
      @spec do_plural_rule(
              LanguageTag.t(),
              number(),
              PluralRule.operand(),
              PluralRule.operand(),
              PluralRule.operand(),
              PluralRule.operand(),
              [integer(), ...] | integer()
            ) :: :zero | :one | :two | :few | :many | :other

      # Function body is the AST of the function which needs to be injected
      # into the function definition.
      for locale_name <- @known_locale_names do
        function_body =
          @rules
          |> Map.get(locale_name)
          |> rules_to_condition_statement(__MODULE__)

        defp do_plural_rule(%LanguageTag{cldr_locale_name: unquote(locale_name)}, n, i, v, w, f, t) do
          # silence unused variable warnings
          _ = {n, i, v, w, f, t}
          unquote(function_body)
        end
      end

      # If we get here then it means that the locale doesn't have a plural rule,
      # but the language might
      defp do_plural_rule(%LanguageTag{} = language_tag, n, i, v, w, f, t) do
        if language_tag.language == language_tag.cldr_locale_name do
          {
            :error,
            {
              Cldr.UnknownPluralRules,
              "No #{@module} plural rules available for #{inspect(language_tag)}"
            }
          }
        else
          language_tag
          |> Map.put(:cldr_locale_name, language_tag.language)
          |> do_plural_rule(n, i, v, w, f, t)
        end
      end
    end
  end
end
