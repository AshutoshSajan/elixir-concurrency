#!/usr/bin/env elixir
defmodule Committer do
  defstruct [:name, :email]

  def list(repo) do
    repo
    |> from_repo
    |> Stream.unfold(fn str ->
      case String.split(str, "\n", parts: 2, trim: true) do
        [] -> nil
        [value] -> {value, ""}
        list -> List.to_tuple(list)
      end
    end)
    |> Stream.map(&String.split(&1, "|", parts: 2))
    |> Stream.map(&Enum.zip([:name, :email], &1))
    |> Stream.map(&struct(Committer, &1))
    |> Stream.uniq(& &1.email)
  end

  def fetch_gravatar(%Committer{email: email}, format \\ :png) do
    request = {gravatar_url(email, format), []}
    http_opts = [timeout: 5000]
    opts = [body_format: :binary, full_result: false]

    case :httpc.request(:get, request, http_opts, opts) do
      {:ok, {200, body}} ->
        {:ok, body}

      {:ok, {num, _}} ->
        {:error, "response code #{num}"}

      {:error, _} = error ->
        error
    end
  end

  @base_url "http://www.gravatar.com/avatar/"
  @url_params "?d=identicon&s=200"
  defp gravatar_url(email, format) do
    '#{@base_url}#{email_hash(email)}.#{format}#{@url_params}'
  end

  defp email_hash(email) do
    email
    |> String.strip()
    |> String.downcase()
    |> hash
    |> Base.encode16(case: :lower)
  end

  defp hash(data), do: :crypto.hash(:md5, data)

  defp from_repo(repo) do
    args = ["log", ~S{--pretty=format:%an|%ae}, "--encoding=UTF-8"]

    case(System.cmd("pwd", [])) do
      {res, 0} ->
        IO.puts("PWD : #{res}")
    end

    case System.cmd("git", args, cd: "../" <> repo) do
      {committers, 0} ->
        committers

      {_, code} ->
        raise RuntimeError, "Getting committers failed with code #{code}"
    end
  end
end

defmodule Download do
  require Logger

  def run(args) do
    IO.inspect(args, label: "args")

    Application.ensure_all_started(:inets)

    {repo, out} = parse_args(args)
    File.mkdir_p!(out)

    File.cd!(out, fn ->
      repo
      |> Committer.list()
      |> Stream.chunk(50, 50, [])
      |> Stream.each(&fetch_and_save_batch/1)
      |> Stream.run()
    end)
  end

  defp fetch_and_save_batch(committers) do
    committers
    |> Enum.map(&Task.async(fn -> fetch_and_save(&1) end))
    |> Enum.map(&Task.await(&1, 10000))
  end

  defp fetch_and_save(%Committer{name: name} = committer) do
    case Committer.fetch_gravatar(committer, :png) do
      {:ok, image} ->
        File.write!("#{name}.png", image)
        Logger.info("downloaded gravatar for #{name}")

      {:error, reason} ->
        Logger.error("failed to download gravatar for #{name}, because: #{inspect(reason)}")
    end
  end

  defp parse_args(args) do
    case OptionParser.parse(args) do
      {_, [repo, out], _} ->
        IO.puts("parsed args #{repo} #{out}\n")
        {repo, out}

      _ ->
        IO.puts("Usage: download repository output_dir\n")
        raise "Wrong arguments given to `download`"
    end
  end
end

Download.run(System.argv())

# iex main.exs stickers out
# "out" is the output folder where gravatars will be saved
# "stickers" the repository for which you want to download the gravatars,
# and you need to clone the repo in the project root
