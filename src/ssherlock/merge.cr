module Ssherlock
  # Deep-merge `override` onto `base`. Nested hashes merge recursively; a null
  # value in `override` knocks out (removes) the inherited key. Anything that is
  # not a hash-on-both-sides is replaced by `override`.
  def self.deep_merge(base : YAML::Any, override : YAML::Any) : YAML::Any
    bh = base.as_h?
    oh = override.as_h?
    return override unless bh && oh

    result = {} of YAML::Any => YAML::Any
    bh.each { |k, v| result[k] = v }

    oh.each do |k, v|
      if v.raw.nil?
        result.delete(k)
      elsif existing = result[k]?
        result[k] = deep_merge(existing, v)
      else
        result[k] = v
      end
    end

    YAML::Any.new(result)
  end
end
