module Crig
  ALPHABET       = "_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  DEFAULT_ID_LEN = 21

  def self.generate_id : String
    generate_id_with_len(DEFAULT_ID_LEN)
  end

  def self.generate_id_with_len(len : Int32) : String
    String.build(len) do |io|
      len.times do
        idx = Random::Secure.rand(ALPHABET.size)
        io << ALPHABET[idx]
      end
    end
  end
end
