defmodule Ecto.Atom do
  @moduledoc false
  @behaviour Ecto.Type

  def type, do: :string

  def cast(value) when is_atom(value), do: {:ok, value}
  def cast(_), do: :error

  def load(value), do: {:ok, String.to_existing_atom(value)}

  def dump(value) when is_atom(value), do: {:ok, Atom.to_string(value)}
  def dump(_), do: :error

  def embed_as(_) do
    :self
  end

  def equal?(term1, term2) do
    term1 === term2
  end
end
