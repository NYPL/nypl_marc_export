class MARCCustomFieldSerialize

  def initialize(record)
    @record = record
  end

  def leader_string
    result = @record.leader_string
    #changing 8th position to 'a'
    result[8] = 'a'
    result

  end

  def controlfield_string
    result = @record.controlfield_string
  end

  def controlfields
    cf = []
    org_codes = %w(NN NN-L NN-PD NN-MUS NN-Sc NN-RHA NN-BGC NN-JD)
    org_code = get_repo_org_code
    cf << add_003_tag(org_code) if org_codes.include?(org_code)
    cf << add_005_tag
    @record.controlfields = cf
  end

  def datafields

    extra_fields = []
    @field_pairs = []

    extra_fields << add_024_tag
    extra_fields << add_035_tag
    extra_fields << add_853_tag

    if @record.aspace_record['top_containers']
      @field_pairs << add_901
      @field_pairs << add_910
      @field_pairs << add_946
      @field_pairs << add_949_fixed
      top_containers = @record.aspace_record['top_containers']
      Log.info("[nyu_marcxml DEBUG] top_containers=#{top_containers.map { |k, v| {id: k, type: v[:type], indicator: v[:indicator]} }.inspect}")
      sort_top_containers(top_containers).each{ |id|
        info = top_containers[id[0]]
        @field_pairs << add_949_tag(info)
      }
    end

    @sort_combined = (@record.datafields + extra_fields).sort_by(&:tag)
    # 863 and 949 pairs are not to be sorted
    # sticking them at the end since the highest tag
    # before 863 is 856
    # this is a hard coded assumption but it's faster
    # There is a method below that does not have that assumption
    # Will call in case things change in marc record
    @sort_combined + @field_pairs


    # the method below is in case there are
    # marc tags higher than 863 in the marc record
    # and the pairs need to be inserted in order
    # not calling this now because it's slower
    # arrange_datafields
  end

  # Sorts top_containers (a hash of uri => info) primarily by container type,
  # then by indicator using a "natural sort": digit runs are compared
  # numerically (so "2" sorts before "10"), non-digit runs are compared as
  # plain strings, and digit tokens always sort before non-digit tokens at
  # the same position. This mirrors the numeric ICU collation ArchivesSpace
  # itself uses to sort the Indicator column (see indicator_u_icusort /
  # the sort_icu fieldType with numeric="true" in solr/schema.xml), and
  # unlike a plain Array#<=> comparison, it never raises when indicators of
  # different "shapes" are compared (e.g. a purely numeric indicator like
  # "5" against a mixed one like "AMI 1 (Audio and Moving Image items)").
  def sort_top_containers(top_containers)
    top_containers.sort do |(_, v1), (_, v2)|
      type_cmp = v1[:type].to_s <=> v2[:type].to_s
      next type_cmp unless type_cmp == 0

      compare_natural_sort_tokens(tokenize_for_natural_sort(v1[:indicator]),
                                   tokenize_for_natural_sort(v2[:indicator]))
    end
  end

  # Splits a string into alternating runs of digits and non-digits, turning
  # each digit run into an Integer (e.g. "AMI 10" => ["AMI ", 10]).
  def tokenize_for_natural_sort(str)
    str.to_s.scan(/\D+|\d+/).map { |token| token =~ /\A\d+\z/ ? token.to_i : token }
  end

  # Compares two token arrays produced by tokenize_for_natural_sort.
  # Tokens are compared position by position: Integer vs Integer compares
  # numerically, String vs String compares lexicographically, and when the
  # types differ at a position the Integer token always sorts first (digits
  # before letters), matching ICU numeric collation. If one array is a
  # prefix of the other (same tokens up to the shorter length), the shorter
  # array sorts first.
  def compare_natural_sort_tokens(tokens1, tokens2)
    tokens1.zip(tokens2).each do |t1, t2|
      return 1 if t2.nil?
      cmp = compare_natural_sort_token(t1, t2)
      return cmp unless cmp == 0
    end

    tokens1.length <=> tokens2.length
  end

  def compare_natural_sort_token(t1, t2)
    if t1.is_a?(Integer) && t2.is_a?(Integer)
      t1 <=> t2
    elsif t1.is_a?(String) && t2.is_a?(String)
      t1 <=> t2
    elsif t1.is_a?(Integer)
      -1
    else
      1
    end
  end

  def arrange_datafields
    min_tag = 863
    last_index = nil
    final_results = []
    # Assumed that sort_combined is sorted
    # in tag order
    @sort_combined.each_with_index do |f,i|
      last_index = i if f.tag.to_i < min_tag
    end
    if last_index == @sort_combined.index(@sort_combined.last)
      final_results = @sort_combined + @field_pairs
    elsif last_index < @sort_combined.index(@sort_combined.last)
      #slice and dice
      temp_array = []
      @sort_combined.slice(0..last_index).each do |i|
        temp_array << i
      end
      @field_pairs.each { |f| temp_array << f }
      start = last_index + 1
      array_last_index = @sort_combined.index(@sort_combined.last)
      final_results = temp_array + @sort_combined.slice(start..array_last_index)
    else
      raise "ERROR: Please check data"
    end

    final_results

  end


  def get_datafield_hash(tag,ind1,ind2)
    {tag: tag, ind1: ind1, ind2: ind2}
  end

  def get_subfield_hash(code,value)
    {code:code, value:value}
  end

  def get_controlfield_hash(tag,text)
    {tag:tag, text: text}
  end


  def add_005_tag
    value = format_timestamp
    controlfield_hsh = get_controlfield_hash('005',value)
    cf = NYUCustomTag.new(controlfield_hsh)
    cf.add_controlfield_tag
  end

  def add_003_tag(org_code)
    controlfield_hsh = get_controlfield_hash('003',org_code)
    cf = NYUCustomTag.new(controlfield_hsh)
    cf.add_controlfield_tag
  end
  def add_024_tag
    subfields_hsh = {}
    value = "(#{get_repo_org_code})#{check_multiple_ids}"
    datafield_hsh = get_datafield_hash('024','7',' ')
    subfields_hsh[1] = get_subfield_hash('a',value)
    subfields_hsh[2] = get_subfield_hash('2','local')
    datafield = NYUCustomTag.new(datafield_hsh,subfields_hsh)
    datafield.add_datafield_tag
  end
  def add_035_tag
    org_code = get_repo_org_code
    value = "(#{get_repo_org_code})#{check_multiple_ids}-#{format_timestamp('date')}"
    subfields_hsh = {}
    datafield_hsh = get_datafield_hash('035','','')
    subfields_hsh[1] = get_subfield_hash('a',value)
    datafield = NYUCustomTag.new(datafield_hsh,subfields_hsh)
    datafield.add_datafield_tag
  end

  def add_853_tag
    subfields_hsh = {}
    datafield_hsh = get_datafield_hash('853','0','0')
    # have to have a hash by position as the key
    # since the subfield positions matter
    subfields_hsh[1] = get_subfield_hash('8','1')
    subfields_hsh[2] = get_subfield_hash('a','Box')
    datafield = NYUCustomTag.new(datafield_hsh,subfields_hsh)
    datafield.add_datafield_tag
  end

  def add_863_tag(info)
    subfields_hsh = {}
    datafield_hsh = get_datafield_hash('863','','')
    # have to have a hash by position as the key
    # since the subfield positions matter
    subfields_hsh[1] = get_subfield_hash('8',"1.#{info[:indicator]}")
    subfields_hsh[2] = get_subfield_hash('a',info[:indicator])
    subfields_hsh[3] = get_subfield_hash('p',info[:barcode]) if info[:barcode]
    datafield = NYUCustomTag.new(datafield_hsh,subfields_hsh)
    datafield.add_datafield_tag
  end

  def add_901
    inits = generate_signature
    df1 = NYUCustomTag.new(get_datafield_hash('901', ' ', ' '), {0 => get_subfield_hash('a', inits[0]), 1 => get_subfield_hash('b', inits[1])})
    return df1.add_datafield_tag
  end

  def add_910
    df1 = NYUCustomTag.new(get_datafield_hash('910', ' ', ' '), {0 => get_subfield_hash('a', 'RL')})
    return df1.add_datafield_tag
  end

  def add_946
    df1 = NYUCustomTag.new(get_datafield_hash('946', ' ', ' '), {0 => get_subfield_hash('a', 'm')})
    return df1.add_datafield_tag
  end

  def add_949_fixed
    df1 = NYUCustomTag.new(get_datafield_hash('949', ' ', ' '), {0 => get_subfield_hash('a', '*B1=7;b2=p; recs=oclcgw;')})
    return df1.add_datafield_tag
  end

  def add_949_tag(info)
    subfields_hsh = {}
    inits = generate_signature
    datafield_hsh = get_datafield_hash('949',' ','1')
    repo_hash = get_repo_code_values(info)
    # have to have a hash by position as the key
    # since the subfield positions matter
    subfields_hsh[0] = get_subfield_hash('z','8528')
    subfields_hsh[1] = generate_subfield_a
    subfields_hsh[2] = get_subfield_hash('l', repo_hash[:l])
    subfields_hsh[3] = get_subfield_hash('i', info[:barcode]) if info[:barcode]
    subfields_hsh[4] = get_subfield_hash('c', "#{info[:type]} #{info[:indicator]}")
    subfields_hsh[5] = get_subfield_hash('t','021')
    subfields_hsh[6] = get_subfield_hash('h', repo_hash[:h])
    subfields_hsh[7] = get_subfield_hash('s','-')
    subfields_hsh[8] = get_subfield_hash('o',repo_hash[:o])
    subfields_hsh[9] = get_subfield_hash('u',repo_hash[:u])
    subfields_hsh[10] = get_subfield_hash('v', inits[1] + '/' + inits[0])

    datafield = NYUCustomTag.new(datafield_hsh,subfields_hsh)
    datafield.add_datafield_tag
  end

  def get_repo_org_code
    @record.aspace_record['repository']['_resolved']['org_code']
  end

  def get_record_repo_value
    code = @record.aspace_record['repository']['_resolved']['repo_code']
    code
  end

  # this contains standard destinations for items and OPAC/item messages
  # for MSS, this is central; otherwise, this is ReCAP
  # subfield u (item msg): u = supervised use, - = none, m = custom (use $m)
  # subfield o (opac msg): u = supervised use, 2 = adv use
  def get_allowed_values
    allowed_values = {}
    allowed_values['mss'] = {l: 'mao82', h: '033', u: '-', o: '4'}
    allowed_values['the'] = {l: 'rcpt8', h: '221', u: 'u', o: 'u'}
    allowed_values['dan'] = {l: 'rcpd8', h: '221', u: 'u', o: 'u'}
    allowed_values['mus'] = {l: 'rcpm8', h: '221', u: 'u', o: 'u'}
    allowed_values['scm'] = {l: 'rccd8', h: '224', u: '-', o: '2'}
    allowed_values['rha'] = {l: 'myh32', h: '032', u: 'u', o: 'u'}
    allowed_values['brg'] = {l: 'mae82', h: '033', u: '-', o: '2'}
    allowed_values['map'] = {l: 'map82', h: '033', u: '-', o: '2'}
    allowed_values['lhg'] = {l: 'rcmg2', h: '222', u: 'u', o: '2'}
    allowed_values['scp'] = {l: 'rcce8', h: '224', u: 'u', o: 'u'}
    # we don't have these values right now, so just return empty strings catalogers can replace
    allowed_values['scl'] = {l: '', h: '', u: '-', o: '2'}
    allowed_values['grd'] = {l: '', h: '', u: '-', o: '2'}
    allowed_values['jws'] = {l: '', h: '', u: '-', o: '2'}
    allowed_values['cps'] = {l: '', h: '', u: '-', o: '2'}
    allowed_values['phg'] = {l: '', h: '', u: '-', o: '2'}
    

    # rspec repo present for testing
    allowed_values['rspec'] = {l: 'rspec00', h: '999'}
    allowed_values
  end

  def get_repo_code_values(container_info)
    repo_code = nil
    repo_value = get_record_repo_value
    # returning the repo value from the record
    # in a consistent case
    record_repo_value = repo_value.downcase if repo_value

    # complex checks to see where an item should be routed
    # based on profile + holding repository
    if (record_repo_value.eql?('the') && ['19', '20', '21', '23', '24', '25', '31', '32', '33', '38', '39'].include?(container_info[:profile_id])) \
      || (record_repo_value.eql?('dan') && ['31', '32', '33', '38', '39'].include?(container_info[:profile_id])) \
      || (record_repo_value.eql?('mus') && ['19', '20', '21', '31', '32', '33', '38', '39'].include?(container_info[:profile_id])) \
      || (record_repo_value.eql?('scm') && ['19', '20', '21', '31', '32', '33', '38', '39'].include?(container_info[:profile_id]))
      vals = get_special_values
    else
      vals = get_allowed_values
    end

    # get subfield values for repo codes
    vals.each_key { |code|
      case record_repo_value
      when code
        repo_code = vals[code]
      end
    }
    unless repo_code
      raise "ERROR: Repo code must be one of these: #{get_allowed_values.keys}
      and not this value: #{record_repo_value}"
    end
    repo_code
  end

  def process_repo_code
    subfields = {}
    # get subfield values for repo code
    repo_code = get_repo_code_values
    # creating a subfield hash
    repo_code.each_key{ |code|
      position = code.to_s == 'b' ? 2 : 3
      subfields[position] = get_subfield_hash(code,repo_code[code])
    }
    subfields
  end

  def check_multiple_ids
    j_id = @record.aspace_record['id_0']
    j_other_ids = []
    if @record.aspace_record['id_1'] or @record.aspace_record['id_2'] or
        @record.aspace_record['id_3']
      j_other_ids << @record.aspace_record['id_1']
      j_other_ids << @record.aspace_record['id_2']
      j_other_ids << @record.aspace_record['id_3']
      # adding the first id as the first element of the array
      j_other_ids.unshift(j_id)
      j_other_ids.compact!
      j_other_ids = j_other_ids.join(".")
    end
    # if no other ids, assign id_0 else assign the whole array of ids
    j_id = j_other_ids.size == 0 ? j_id : j_other_ids
  end

  def generate_subfield_j
    id = check_multiple_ids
    get_subfield_hash('j',id)
  end

  def location_hsh
    {
        "Clancy Cullen [Offsite]" => "DM",
        "Bern Dibner Library [Offsite Prep]" => "ON",
        "Bobst [Offsite Prep]" => "ON"
    }
  end

  def get_location(location_info)
    loc_hsh = location_hsh
    # if location is one of the keys in location_hash,
    # output the value
    # else a blank subfield
    location = loc_hsh.key?(location_info) ? loc_hsh[location_info] : ''
    # creating a subfield hash
    get_subfield_hash('s',location)
  end

  def format_timestamp(type = 'timestamp')
    ts = @record.aspace_record['user_mtime']
    value = nil
    case type
    when 'timestamp'
      value = ts.gsub(/-|T|:|Z/,"") + ".0"
    when 'date'
      value = ts.split('T')[0]
      value = value.gsub('-','')
    end
    raise "ERROR: incorrect argument passed: #{type}. Should be either date or timestamp" if value.nil?

    value
  end

  def generate_subfield_a
    id = generate_collection_call_number
    get_subfield_hash('a',id)
  end
  
  def generate_collection_call_number
    user_defined = @record.aspace_record['user_defined']
    call_number = user_defined && user_defined['string_1'] # "string_1" in user_defined holds the call number
    call_number || ''
  end


  def generate_signature

    # if we want to, we could have this generate the initials
    # of the person that generated the MARC record.
    # but for now, we'll just output ---, and they can find/replace
    # it with their initials when they catalog.

    # The resource record itself has no 'user' field (only 'last_modified_by',
    # a username string), so look up the user currently performing the export
    # (i.e. the logged-in user running this request) and fetch their
    # department from the user table.
    current_username = RequestContext.get(:current_username)
    current_user = current_username ? User.where(username: current_username).first : nil
    department = current_user ? current_user.department : nil

    if department.eql?('Archives Unit')
      dept = 'archv'
    elsif department.eql?('Special Formats Processing')
      dept = 'sfp'
    else
      dept = '---'
    end

    initials = '---'

    return [initials, dept]
  end

end
