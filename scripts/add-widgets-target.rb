#!/usr/bin/env ruby
# frozen_string_literal: false
#
# Adds the Live-Activity widget extension "IndoorCoachWidgets" to IndoorCoach.xcodeproj and embeds it in the iOS app
# (Embed Foundation Extensions). Idempotent: does nothing when the target already exists.
#
#   ruby scripts/add-widgets-target.rb
#
# Why Nanaimo and not Xcodeproj::Project: see add-bridge-target.rb (file-system-synchronized groups, objectVersion 77).

require 'xcodeproj'
require 'nanaimo'

ROOT = File.expand_path('..', __dir__)
PBXPROJ = File.join(ROOT, 'IndoorCoach.xcodeproj', 'project.pbxproj')

APP_NAME = 'IndoorCoach'.freeze
EXT_NAME = 'IndoorCoachWidgets'.freeze

# value with a "/* comment */" annotation, as Xcode writes object references
Ref = Struct.new(:id, :comment)

def nano(v)
  case v
  when Ref then Nanaimo::String.new(v.id, " #{v.comment} ")
  when Hash then Nanaimo::Dictionary.new(v.map { |k, x| [Nanaimo::String.new(k.to_s, ''), nano(x)] }.to_h, '')
  when Array then Nanaimo::Array.new(v.map { |x| nano(x) }, '')
  else
    str = v.to_s
    # Xcode only leaves plain identifiers/paths unquoted
    (str =~ %r{\A[A-Za-z0-9_./]+\z} ? Nanaimo::String : Nanaimo::QuotedString).new(str, '')
  end
end

def find(dict, key)
  dict.value.find { |k, _| k.value == key }&.last
end

def id(n)
  format('AC%022d', n)
end

plist = Nanaimo::Reader.new(File.read(PBXPROJ)).parse!
root = plist.root_object
objects = find(root, 'objects')

already = objects.value.values.any? do |o|
  find(o, 'isa')&.value == 'PBXNativeTarget' && find(o, 'name')&.value == EXT_NAME
end
if already
  puts "#{EXT_NAME} existiert bereits – nichts zu tun."
  exit 0
end

def add(objects, oid, comment, hash)
  objects.value[Nanaimo::String.new(oid, " #{comment} ")] = nano(hash)
end

def append_child(objects, parent_id, ref)
  obj = objects.value.find { |k, _| k.value == parent_id }.last
  find(obj, 'children').value << nano(ref)
end

def phase(isa, files = [])
  { 'isa' => isa, 'buildActionMask' => '2147483647', 'files' => files, 'runOnlyForDeploymentPostprocessing' => '0' }
end

# --- ids ---------------------------------------------------------------------------------------------------------
ext_product = id(2001)
ext_group = id(2101)
exception_set = id(2201)
kit_build_file = id(2301)
embed_build_file = id(2302)
ext_frameworks = id(2401)
ext_sources = id(2402)
ext_resources = id(2403)
embed_phase = id(2404)
kit_dependency = id(2501)
proxy = id(2601)
target_dependency = id(2602)
ext_target = id(2701)
ext_debug = id(2801)
ext_release = id(2802)
list_ext = id(2901)

project_obj_id = find(root, 'rootObject').value
project_obj = objects.value.find { |k, _| k.value == project_obj_id }.last
main_group_id = find(project_obj, 'mainGroup').value
products_group_id = find(project_obj, 'productRefGroup').value

app_entry = objects.value.find do |_, o|
  find(o, 'isa')&.value == 'PBXNativeTarget' && find(o, 'name')&.value == APP_NAME
end
abort "Ziel #{APP_NAME} nicht gefunden." unless app_entry
app_target_obj = app_entry.last

exception_comment = "Exceptions for \"#{EXT_NAME}\" folder in \"#{EXT_NAME}\" target"

# --- files & groups ----------------------------------------------------------------------------------------------
add(objects, ext_product, "#{EXT_NAME}.appex",
    'isa' => 'PBXFileReference', 'explicitFileType' => 'wrapper.app-extension', 'includeInIndex' => '0',
    'path' => "#{EXT_NAME}.appex", 'sourceTree' => 'BUILT_PRODUCTS_DIR')
add(objects, ext_group, EXT_NAME,
    'isa' => 'PBXFileSystemSynchronizedRootGroup',
    'exceptions' => [Ref.new(exception_set, exception_comment)],
    'path' => EXT_NAME, 'sourceTree' => '<group>')
add(objects, exception_set, exception_comment,
    'isa' => 'PBXFileSystemSynchronizedBuildFileExceptionSet',
    'membershipExceptions' => ['Info.plist'],
    'target' => Ref.new(ext_target, EXT_NAME))
append_child(objects, main_group_id, Ref.new(ext_group, EXT_NAME))
append_child(objects, products_group_id, Ref.new(ext_product, "#{EXT_NAME}.appex"))

# --- package dependency (shared RecordingActivityAttributes / RecordingLiveState) --------------------------------
add(objects, kit_dependency, 'IndoorCoachKit', 'isa' => 'XCSwiftPackageProductDependency', 'productName' => 'IndoorCoachKit')
add(objects, kit_build_file, 'IndoorCoachKit in Frameworks',
    'isa' => 'PBXBuildFile', 'productRef' => Ref.new(kit_dependency, 'IndoorCoachKit'))

# --- build phases ------------------------------------------------------------------------------------------------
add(objects, ext_frameworks, 'Frameworks', phase('PBXFrameworksBuildPhase', [Ref.new(kit_build_file, 'IndoorCoachKit in Frameworks')]))
add(objects, ext_sources, 'Sources', phase('PBXSourcesBuildPhase'))
add(objects, ext_resources, 'Resources', phase('PBXResourcesBuildPhase'))

embed_comment = "#{EXT_NAME}.appex in Embed Foundation Extensions"
add(objects, embed_build_file, embed_comment,
    'isa' => 'PBXBuildFile', 'fileRef' => Ref.new(ext_product, "#{EXT_NAME}.appex"),
    'settings' => { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] })
add(objects, embed_phase, 'Embed Foundation Extensions',
    'isa' => 'PBXCopyFilesBuildPhase', 'buildActionMask' => '2147483647', 'dstPath' => '', 'dstSubfolderSpec' => '13',
    'files' => [Ref.new(embed_build_file, embed_comment)],
    'name' => 'Embed Foundation Extensions', 'runOnlyForDeploymentPostprocessing' => '0')

# --- target ------------------------------------------------------------------------------------------------------
add(objects, ext_target, EXT_NAME,
    'isa' => 'PBXNativeTarget',
    'buildConfigurationList' => Ref.new(list_ext, "Build configuration list for PBXNativeTarget \"#{EXT_NAME}\""),
    'buildPhases' => [Ref.new(ext_sources, 'Sources'), Ref.new(ext_frameworks, 'Frameworks'), Ref.new(ext_resources, 'Resources')],
    'buildRules' => [], 'dependencies' => [],
    'fileSystemSynchronizedGroups' => [Ref.new(ext_group, EXT_NAME)],
    'name' => EXT_NAME,
    'packageProductDependencies' => [Ref.new(kit_dependency, 'IndoorCoachKit')],
    'productName' => EXT_NAME,
    'productReference' => Ref.new(ext_product, "#{EXT_NAME}.appex"),
    'productType' => 'com.apple.product-type.app-extension')

add(objects, proxy, 'PBXContainerItemProxy',
    'isa' => 'PBXContainerItemProxy', 'containerPortal' => Ref.new(project_obj_id, 'Project object'),
    'proxyType' => '1', 'remoteGlobalIDString' => ext_target, 'remoteInfo' => EXT_NAME)
add(objects, target_dependency, 'PBXTargetDependency',
    'isa' => 'PBXTargetDependency', 'target' => Ref.new(ext_target, EXT_NAME),
    'targetProxy' => Ref.new(proxy, 'PBXContainerItemProxy'))

# the app builds the extension first and embeds it
find(app_target_obj, 'buildPhases').value << nano(Ref.new(embed_phase, 'Embed Foundation Extensions'))
find(app_target_obj, 'dependencies').value << nano(Ref.new(target_dependency, 'PBXTargetDependency'))

# --- build configurations ----------------------------------------------------------------------------------------
settings = {
  'APPLICATION_EXTENSION_API_ONLY' => 'YES',
  'CODE_SIGN_STYLE' => 'Automatic',
  'CURRENT_PROJECT_VERSION' => '1',
  'DEVELOPMENT_TEAM' => '',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'INFOPLIST_FILE' => 'IndoorCoachWidgets/Info.plist',
  'INFOPLIST_KEY_CFBundleDisplayName' => 'IndoorCoach Live',
  'IPHONEOS_DEPLOYMENT_TARGET' => '18.0',
  'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
  'MARKETING_VERSION' => '0.1',
  'PRODUCT_BUNDLE_IDENTIFIER' => 'app.indoorcoach.personal.widgets',
  'PRODUCT_NAME' => '$(TARGET_NAME)',
  'SDKROOT' => 'iphoneos',
  'SKIP_INSTALL' => 'YES',
  'SUPPORTED_PLATFORMS' => 'iphoneos iphonesimulator',
  'SUPPORTS_MACCATALYST' => 'NO',
  'SWIFT_EMIT_LOC_STRINGS' => 'YES',
  'SWIFT_VERSION' => '6.0',
  'TARGETED_DEVICE_FAMILY' => '1'
}
{ ext_debug => 'Debug', ext_release => 'Release' }.each do |cid, name|
  add(objects, cid, name, 'isa' => 'XCBuildConfiguration', 'buildSettings' => settings, 'name' => name)
end
add(objects, list_ext, "Build configuration list for PBXNativeTarget \"#{EXT_NAME}\"",
    'isa' => 'XCConfigurationList',
    'buildConfigurations' => [Ref.new(ext_debug, 'Debug'), Ref.new(ext_release, 'Release')],
    'defaultConfigurationIsVisible' => '0', 'defaultConfigurationName' => 'Release')

# --- project object ----------------------------------------------------------------------------------------------
find(project_obj, 'targets').value << nano(Ref.new(ext_target, EXT_NAME))
attrs = find(find(project_obj, 'attributes'), 'TargetAttributes')
attrs.value[Nanaimo::String.new(ext_target, '')] = nano('CreatedOnToolsVersion' => '27.2')

File.write(PBXPROJ, Nanaimo::Writer::PBXProjWriter.new(plist).write)
puts "#{EXT_NAME} hinzugefügt und in #{APP_NAME} eingebettet."
