# The engine evaluates preload scripts with self = nil (binding-mri: topSelf
# isn't set yet), so an instance variable assigned at the top level - also
# inside a block such as Yami.on_tick { @x ||= ... } - raises FrozenError.
# Fail if any of Yami's scripts does that.
SCRIPTS = File.expand_path("../../app/src/main/assets/yami/scripts", __dir__)
SCOPES = %i[DEFN DEFS CLASS MODULE SCLASS].freeze
$found = []

def walk(node, file, scoped)
  return unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)
  scoped ||= SCOPES.include?(node.type)
  # define_method / instance_eval blocks run with their own self
  if !scoped && node.type == :ITER
    call = node.children.first
    if call.is_a?(RubyVM::AbstractSyntaxTree::Node) && %i[CALL FCALL QCALL].include?(call.type)
      mid = call.type == :FCALL ? call.children[0] : call.children[1]
      if %i[send __send__ public_send].include?(mid)   # x.send(:define_method, ...)
        args = call.children.last
        first = args.children.first if args.is_a?(RubyVM::AbstractSyntaxTree::Node)
        mid = first.children.first if first.is_a?(RubyVM::AbstractSyntaxTree::Node) && %i[LIT SYM].include?(first.type)
      end
    end
    scoped = true if %i[define_method define_singleton_method instance_eval instance_exec class_eval module_eval].include?(mid)
  end
  if !scoped && %i[IASGN OP_ASGN_OR OP_ASGN_AND].include?(node.type)
    target = node.type == :IASGN ? node : node.children.first
    if target.is_a?(RubyVM::AbstractSyntaxTree::Node) && (target.type == :IASGN || target.type == :IVAR)
      $found << "#{File.basename(file)}:#{node.first_lineno}"
    end
  end
  node.children.each { |c| walk(c, file, scoped) }
end

Dir[File.join(SCRIPTS, "*.rb")].sort.each do |f|
  walk(RubyVM::AbstractSyntaxTree.parse(File.read(f, encoding: "UTF-8")), f, false)
end
if $found.empty?
  puts "PASS no top-level instance variables in Yami's scripts"
  puts "ALL PASS"
else
  puts "FAIL top-level instance variables (self is nil in the engine): #{$found.uniq.join(', ')}"
  puts "1 FAILED"
  exit 1
end
