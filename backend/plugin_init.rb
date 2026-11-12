require_relative 'lib/marc_custom_field_serialize'
require_relative 'lib/nyu_custom_tag'
require_relative 'lib/nyu_custom_serializer_marc21'
require_relative 'lib/aspace_extensions'
require_relative 'lib/remove_5xx_fields'

MARCSerializer.add_decorator(MARCCustomFieldSerialize)
MARCSerializer.add_decorator(Remove5xxFields)
Log.info("[DEBUG plugin_init.rb] MARCSerializer object_id=#{MARCSerializer.object_id} decorators_after_add=#{MARCSerializer.instance_variable_get(:@decorators).inspect}")
