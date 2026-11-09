class Remove5xxFields

  def initialize(record)
    @record = record
  end

  def leader_string
    @record.leader_string
  end

  def controlfield_string
    @record.controlfield_string
  end

  def controlfields
    @record.controlfields
  end

  def datafields
    # Filter out all 5xx fields (tags starting with '5')
    @record.datafields.reject { |field| field.tag.start_with?('5') }
  end
end
