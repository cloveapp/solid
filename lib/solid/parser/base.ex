defmodule Solid.Parser.Base do
  defmacro __using__(opts) do
    custom_tag_modules = Keyword.get(opts, :custom_tags, [])

    quote location: :keep, bind_quoted: [custom_tag_modules: custom_tag_modules] do
      import NimbleParsec
      alias Solid.Parser.{Literal, Variable, Argument, BaseTag}

      defp when_join(whens) do
        for {:when, [value: value, result: result]} <- whens, into: %{} do
          {value, result}
        end
      end

      space = Literal.whitespace(min: 0)

      opening_object = string("{{")
      opening_wc_object = string("{{-")
      closing_object = string("}}")
      closing_wc_object = string("-}}")

      opening_tag = BaseTag.opening_tag()
      closing_tag = BaseTag.closing_tag()
      opening_wc_tag = string("{%-")

      closing_wc_object_and_whitespace =
        closing_wc_object
        |> concat(Literal.whitespace(min: 0))
        |> ignore()

      object =
        ignore(opening_object)
        # At this stage whitespace control has been handled as part of the liquid_entry
        |> ignore(optional(string("-")))
        |> ignore(space)
        |> lookahead_not(closing_object)
        |> tag(Argument.argument(), :argument)
        |> optional(tag(repeat(Argument.filter()), :filters))
        |> ignore(space)
        |> ignore(choice([closing_wc_object_and_whitespace, closing_object]))
        |> tag(:object)

      base_tags = [
        Solid.Tag.Break.spec(),
        Solid.Tag.Continue.spec(),
        Solid.Tag.Counter.spec(),
        Solid.Tag.Comment.spec(),
        Solid.Tag.Assign.spec(),
        Solid.Tag.Capture.spec(),
        Solid.Tag.If.spec(),
        Solid.Tag.Case.spec(),
        Solid.Tag.For.spec(),
        Solid.Tag.Raw.spec(),
        Solid.Tag.Cycle.spec(),
        Solid.Tag.Render.spec()
      ]

      custom_tags =
        if custom_tag_modules != [] do
          custom_tag_modules
          |> Enum.uniq()
          |> Enum.map(fn {tag_name, module} ->
            tag(module.spec(), module)
          end)
        end

      all_tags = base_tags ++ (custom_tags || [])

      tags =
        choice(all_tags)
        |> tag(:tag)

      text =
        lookahead_not(
          choice([
            Literal.whitespace(min: 1)
            |> concat(opening_wc_object),
            Literal.whitespace(min: 1)
            |> concat(opening_wc_tag),
            opening_object,
            opening_tag
          ])
        )
        |> utf8_string([], 1)
        |> times(min: 1)
        |> reduce({Enum, :join, []})
        |> tag(:text)

      leading_whitespace =
        Literal.whitespace(min: 1)
        |> lookahead(choice([opening_wc_object, opening_wc_tag]))
        |> ignore()

      defcombinatorp(:liquid_entry, repeat(choice([object, tags, text, leading_whitespace])))

      defparsec(:parse, parsec(:liquid_entry) |> eos())
    end
  end
end
