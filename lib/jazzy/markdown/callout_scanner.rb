module Jazzy::Markdown
  # This code manipulates the markdown AST before it is turned into HTML to
  # change eg. `- warning:` from list-items to box-outs, and to separate returns
  # and parameters documentation.

  class CommonMarker::Node
    # Extensions to help identify and process callouts.
    # A callout may exist when there is a List->ListItem->Para->Text node
    # hierarchy and the text matches a certain format.

    attr_reader :callout_param_name

    # Four slightly different formats wrapped up here:
    #   Callout(XXXX XXXX):YYYY
    #   Parameter XXXX: YYYY   (Swift)
    #   Parameter: XXXX YYYY   (ObjC via SourceKitten)
    #   XXXX:YYYYY
    def callout_parts
      if string_content =~ /\A\s*Callout\((.+)\)\s*:\s*(.*)\Z/mi
        @callout_custom = $1
        @callout_rest = $2
      elsif string_content =~ /\A\s*Parameter\s+(\S+)\s*:\s*(.*)\Z/mi ||
        string_content =~ /A\s*Parameter\s*:\s*(\S+)\s*(.*)\Z/mi
        @callout_param_name = $1
        @callout_rest = $2
      elsif string_content =~ /\A\s*(\S+)\s*:\s*(.*)\Z/mi
        @callout_type = $1
        @callout_rest = $2
      end
      @callout_rest
    end

    def callout_custom?
      @callout_custom
    end

    def callout_type
      @callout_type || @callout_custom
    end

    def callout_param?
      @callout_param_name
    end

    def callout_parameters?
      callout_type.downcase == 'parameters'
    end

    def callout_returns?
      callout_type.downcase == 'returns'
    end

    # Edit the node to leave just the callout body
    def remove_callout_type!
      self.string_content = @callout_rest
    end

    # Iterator vending |list_item_node, text_node| for callout-looking children
    def each_callout
      return unless type == :list && list_type == :bullet_list
      each do |child_node|
        next unless child_node.type == :list_item
        para_node = child_node.first_child
        next unless para_node && para_node.type == :paragraph
        text_node = para_node.first_child
        next unless text_node && text_node.type == :text
        yield child_node, text_node if text_node.callout_parts
      end
    end
  end

  # https://github.com/apple/swift/blob/master/include/swift/Markup/SimpleFields.def
  # Plus 'example' from playgrounds.
  NORMAL_CALLOUTS = %w[attention
                       author
                       authors
                       bug
                       complexity
                       copyright
                       date
                       experiment
                       important
                       invariant
                       localizationkey
                       mutatingvariant
                       nonmutatingvariant
                       note
                       postcondition
                       precondition
                       remark
                       remarks
                       throws
                       requires
                       seealso
                       since
                       tag
                       todo
                       version
                       warning
                       keyword
                       recommended
                       recommendedover
                       example].freeze

  class CalloutScanner
    attr_reader :returns_doc, :parameters_docs, :enum_cases_docs

    def initialize
      @returns_doc = nil
      @parameters_docs = {}
      @enum_cases_docs = {}
    end

    def scan(doc)
      doc.each do |child|
        child.each_callout do |list_item_node, text_node|
          callout = text_node.callout_type

          if text_node.callout_param?
            puts('param')
          elsif text_node.callout_parameters?
            params_list_node = text_node.parent.next
            next unless params_list_node
            puts('parameters')
            params_list_node.each_callout do |param_list_item_node, param_text_node|
              puts(" param #{param_text_node.callout_type}")
            end
            next
          elsif text_node.callout_returns?
            puts('returns')
          elsif text_node.callout_custom?
            create_callout(child, list_item_node, text_node)
          elsif NORMAL_CALLOUTS.include?(text_node.callout_type.downcase)
            create_callout(child, list_item_node, text_node)
          else
            puts('remember for enum')
          end
        end

        # Finally chuck the list if nothing left inside
        child.delete unless child.first_child 
      end
    end

    def create_callout(list_node, list_item_node, text_node)
      # Set up html intro to callout
      html_in_node = CommonMarker::Node.new(:html)
      # XXX need to slugify callout type
      html_in_node.string_content =
        "<div class='aside aside-#{text_node.callout_type}'>\n" +
        "<p class='aside-title'>#{text_node.callout_type}</p>"
      list_node.insert_before(html_in_node)

      # Body of the callout
      text_node.remove_callout_type!
      while node = list_item_node.first_child do
        list_node.insert_before(node)
      end
      list_item_node.delete

      # HTML outro
      html_out_node = CommonMarker::Node.new(:html)
      html_out_node.string_content = '</div>'
      list_node.insert_before(html_out_node)
    end
  end
end