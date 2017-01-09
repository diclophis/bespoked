#!/usr/bin/env ruby

require 'yaml'
require 'psych'
require 'uri'

registry_domain = (ARGV[0] && (ARGV[0])) || raise
image_name = ARGV[1] || raise
image_tag = ARGV[2] || raise

class DocumentStreamHandler < Psych::TreeBuilder
  def initialize &block
    super
    @block = block
  end

  def end_document implicit_end = !streaming?
    @last.implicit_end = implicit_end
    @block.call pop
  end

  def start_document version, tag_directives, implicit
    n = Psych::Nodes::Document.new version, tag_directives, implicit
    push n
  end
end

rc_yml_path = File.join("kubernetes", "rc.yml")

document_handler_switch = Proc.new do |document|
  add_to_pending_documents = false

  description = document.to_ruby
  kind = description["kind"]
  name = description["metadata"]["name"]

  case kind
    when "Service"

    when "ReplicationController"
      description["spec"]["template"]["spec"]["containers"][0]["image"] = (registry_domain + (image_name + ":" + image_tag))

  else
  end

  puts description.to_yaml
end

handler = DocumentStreamHandler.new(&document_handler_switch)
parser = Psych::Parser.new(handler)
parser.parse(File.read(rc_yml_path), rc_yml_path)
