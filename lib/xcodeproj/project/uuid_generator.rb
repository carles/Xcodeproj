module Xcodeproj
  class Project
    class UUIDGenerator
      def initialize(project)
        @project = project
        @new_objects_by_uuid = {}
        @paths_by_object = {}
      end

      def generate!
        all_objects = @project.objects
        generate_paths(@project.root_object)
        switch_uuids(all_objects)
        verify_no_duplicates!(all_objects)
        fixup_uuid_references
        @project.instance_variable_set(:@generated_uuids, @project.instance_variable_get(:@available_uuids))
        @project.instance_variable_set(:@objects_by_uuid, @new_objects_by_uuid)
      end

      private

      def verify_no_duplicates!(all_objects)
        duplicates = all_objects - @new_objects_by_uuid.values
        raise "[Xcodeproj] Generated duplicate UUIDs:\n\n" <<
          duplicates.map { |d| "#{d.isa} -- #{@paths_by_object[d]}" }.join("\n") unless duplicates.empty?
      end

      def fixup_uuid_references
        fixup = ->(object, attr) do
          if object.respond_to?(attr) && link = @project.objects_by_uuid[object.send(attr)]
            object.send(:"#{attr}=", link.uuid)
          end
        end
        @project.objects.each do |object|
          [:remote_global_id_string, :container_portal, :target_proxy].each do |attr|
            fixup[object, attr]
          end
        end
      end

      def generate_paths(object, path = '')
        @paths_by_object[object] = path

        object.to_one_attributes.each do |attrb|
          obj = attrb.get_value(object)
          generate_paths(obj, path + '/' << attrb.plist_name) if obj
        end

        object.to_many_attributes.each do |attrb|
          attrb.get_value(object).each do |o|
            generate_paths(o, path + '/' << attrb.plist_name << "/#{path_component_for_object(o)}")
          end
        end

        object.references_by_keys_attributes.each do |attrb|
          attrb.get_value(object).each do |dictionary|
            dictionary.each do |key, value|
              generate_paths(value, path + '/' << attrb.plist_name << "/k:#{key}/#{path_component_for_object(value)}")
            end
          end
        end
      end

      def switch_uuids(objects)
        objects.each do |object|
          next unless path = @paths_by_object[object]
          uuid = uuid_for_path(path)
          object.instance_variable_set(:@uuid, uuid)
          @new_objects_by_uuid[uuid] = object
        end
      end

      def uuid_for_path(path)
        Digest::MD5.hexdigest(path).upcase
      end

      def path_component_for_object(object)
        hash = object.to_tree_hash
        tree_hash_to_path(hash)
      end

      def tree_hash_to_path(object, depth = 3)
        return '|' if depth.zero?
        case object
        when Hash
          object.sort.each_with_object('') do |(key, value), string|
            string << key << ':' << tree_hash_to_path(value, depth - 1) << ','
          end
        when Array
          object.map do |value|
            tree_hash_to_path(value, depth - 1)
          end.join(',')
        when String
          object
        else
          raise "[Xcodeproj] Unrecognized object `#{hash}` in #tree_hash_to_path"
        end
      end
    end
  end
end
