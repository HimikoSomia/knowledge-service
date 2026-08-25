class Chunking::TextSplitter
  MAX_CHARS = 2_000

  def initialize(max_chars: MAX_CHARS)
    raise ArgumentError, "max_chars must be positive" unless max_chars.to_i.positive?

    @max_chars = max_chars.to_i
  end

  def split(text)
    text = text.to_s.strip
    return [] if text.blank?
    return [ text ] if text.length <= max_chars

    parts = []
    current = ""
    sentences(text).each do |sentence|
      if sentence.length > max_chars
        parts << current unless current.blank?
        current = ""
        parts.concat(split_by_words(sentence))
      elsif current.length + sentence.length + 1 > max_chars
        parts << current unless current.blank?
        current = sentence
      else
        current = current.empty? ? sentence : "#{current} #{sentence}"
      end
    end

    parts << current unless current.blank?
    parts
  end

  private

  attr_reader :max_chars

  def sentences(text)
    text.scan(/[^.!?\n]+(?:[.!?\n]+|$)/).map(&:strip).reject(&:empty?)
  end

  def split_by_words(text)
    parts = []
    current = ""

    text.split.each do |word|
      if word.length > max_chars
        parts << current unless current.blank?
        current = ""
        parts.concat(word.scan(/.{1,#{max_chars}}/m))
      elsif current.length + word.length + 1 > max_chars
        parts << current unless current.blank?
        current = word
      else
        current = current.empty? ? word : "#{current} #{word}"
      end
    end

    parts << current unless current.blank?
    parts
  end
end
