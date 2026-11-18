#!/usr/bin/env ruby
# frozen_string_literal: false
#
# Adds the macOS menu-bar app target "IndoorCoachBridge" (+ unit-test target "IndoorCoachBridgeTests" and the shared
# scheme) to IndoorCoach.xcodeproj. Idempotent: does nothing when the target already exists.
#
#   ruby scripts/add-bridge-target.rb
#
# Why Nanaimo and not Xcodeproj::Project: the project uses file-system-synchronized groups (objectVersion 77), which
# xcodeproj 1.21 cannot load. The gem's ASCII-plist parser/writer (Nanaimo, a dependency of xcodeproj) round-trips the
# file byte-for-byte, so the new objects are added to the parsed plist without touching the existing ones.

require 'xcodeproj'
require 'nanaimo'

ROOT = File.expand_path('..', __dir__)
PROJECT = File.join(ROOT, 'IndoorCoach.xcodeproj')
PBXPROJ = File.join(PROJECT, 'project.pbxproj')
SCHEME = File.join(PROJECT, 'xcshareddata', 'xcschemes', 'IndoorCoachBridge.xcscheme')

APP_NAME = 'IndoorCoachBridge'.freeze
TEST_NAME = 'IndoorCoachBridgeTests'.freeze

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
  find(o, 'isa')&.value == 'PBXNativeTarget' && find(o, 'name')&.value == APP_NAME
end
if already
  puts "#{APP_NAME} existiert bereits – nichts zu tun."
  exit 0
end

def add(objects, oid, comment, hash)
  objects.value[Nanaimo::String.new(oid, " #{comment} ")] = nano(hash)
end

def append_child(objects, parent_id, ref)
  obj = objects.value.find { |k, _| k.value == parent_id }.last
  find(obj, 'children').value << nano(ref)
end

# --- ids ---------------------------------------------------------------------------------------------------------
app_product = id(1001)
test_product = id(1002)
bridge_group = id(1101)
tests_group = id(1102)
exception_set = id(1201)
kit_build_file = id(1301)
app_frameworks = id(1401)
app_sources = id(1402)
app_resources = id(1403)
test_frameworks = id(1411)
test_sources = id(1412)
test_resources = id(1413)
kit_dependency = id(1501)
app_target = id(1701)
test_target = id(1702)
list_app = id(1902)
list_test = id(1903)
app_debug = id(1801)
app_release = id(1802)
test_debug = id(1803)
test_release = id(1804)
proxy = id(1601)
target_dependency = id(1602)

project_obj_id = find(root, 'rootObject').value
project_obj = objects.value.find { |k, _| k.value == project_obj_id }.last
main_group_id = find(project_obj, 'mainGroup').value
products_group_id = find(project_obj, 'productRefGroup').value
package_ref_id = find(project_obj, 'packageReferences').value.first.value

# --- files & groups ----------------------------------------------------------------------------------------------
add(objects, app_product, 'IndoorCoach Brücke.app',
    'isa' => 'PBXFileReference', 'explicitFileType' => 'wrapper.application', 'includeInIndex' => '0',
    'path' => 'IndoorCoach Brücke.app', 'sourceTree' => 'BUILT_PRODUCTS_DIR')
add(objects, test_product, "#{TEST_NAME}.xctest",
    'isa' => 'PBXFileReference', 'explicitFileType' => 'wrapper.cfbundle', 'includeInIndex' => '0',
    'path' => "#{TEST_NAME}.xctest", 'sourceTree' => 'BUILT_PRODUCTS_DIR')
add(objects, bridge_group, 'Bridge',
    'isa' => 'PBXFileSystemSynchronizedRootGroup',
    'exceptions' => [Ref.new(exception_set, 'Exceptions for "Bridge" folder in "IndoorCoachBridge" target')],
    'path' => 'Bridge', 'sourceTree' => '<group>')
add(objects, tests_group, 'BridgeTests',
    'isa' => 'PBXFileSystemSynchronizedRootGroup', 'path' => 'Bridge/Tests', 'sourceTree' => '<group>')
add(objects, exception_set, 'Exceptions for "Bridge" folder in "IndoorCoachBridge" target',
    'isa' => 'PBXFileSystemSynchronizedBuildFileExceptionSet',
    # test sources are listed one by one (a folder entry is not honoured); add new test files here and re-create
    'membershipExceptions' => ['IndoorCoachBridge.entitlements', 'Info.plist'] +
                              Dir.glob(File.join(ROOT, 'Bridge/Tests/**/*.swift')).sort.map { |f| f.sub("#{ROOT}/Bridge/", '') },
    'target' => Ref.new(app_target, APP_NAME))
append_child(objects, main_group_id, Ref.new(bridge_group, 'Bridge'))
append_child(objects, main_group_id, Ref.new(tests_group, 'BridgeTests'))
append_child(objects, products_group_id, Ref.new(app_product, 'IndoorCoach Brücke.app'))
append_child(objects, products_group_id, Ref.new(test_product, "#{TEST_NAME}.xctest"))

# --- package dependency ------------------------------------------------------------------------------------------
add(objects, kit_dependency, 'IndoorCoachKit', 'isa' => 'XCSwiftPackageProductDependency', 'productName' => 'IndoorCoachKit')
add(objects, kit_build_file, 'IndoorCoachKit in Frameworks',
    'isa' => 'PBXBuildFile', 'productRef' => Ref.new(kit_dependency, 'IndoorCoachKit'))

# --- build phases ------------------------------------------------------------------------------------------------
def phase(isa, files = [])
  { 'isa' => isa, 'buildActionMask' => '2147483647', 'files' => files, 'runOnlyForDeploymentPostprocessing' => '0' }
end
add(objects, app_frameworks, 'Frameworks', phase('PBXFrameworksBuildPhase', [Ref.new(kit_build_file, 'IndoorCoachKit in Frameworks')]))
add(objects, app_sources, 'Sources', phase('PBXSourcesBuildPhase'))
add(objects, app_resources, 'Resources', phase('PBXResourcesBuildPhase'))
add(objects, test_frameworks, 'Frameworks', phase('PBXFrameworksBuildPhase'))
add(objects, test_sources, 'Sources', phase('PBXSourcesBuildPhase'))
add(objects, test_resources, 'Resources', phase('PBXResourcesBuildPhase'))

# --- targets -----------------------------------------------------------------------------------------------------
add(objects, proxy, 'PBXContainerItemProxy',
    'isa' => 'PBXContainerItemProxy', 'containerPortal' => Ref.new(project_obj_id, 'Project object'),
    'proxyType' => '1', 'remoteGlobalIDString' => app_target, 'remoteInfo' => APP_NAME)
add(objects, target_dependency, 'PBXTargetDependency',
    'isa' => 'PBXTargetDependency', 'target' => Ref.new(app_target, APP_NAME),
    'targetProxy' => Ref.new(proxy, 'PBXContainerItemProxy'))

add(objects, app_target, APP_NAME,
    'isa' => 'PBXNativeTarget',
    'buildConfigurationList' => Ref.new(list_app, "Build configuration list for PBXNativeTarget \"#{APP_NAME}\""),
    'buildPhases' => [Ref.new(app_sources, 'Sources'), Ref.new(app_frameworks, 'Frameworks'), Ref.new(app_resources, 'Resources')],
    'buildRules' => [], 'dependencies' => [],
    'fileSystemSynchronizedGroups' => [Ref.new(bridge_group, 'Bridge')],
    'name' => APP_NAME,
    'packageProductDependencies' => [Ref.new(kit_dependency, 'IndoorCoachKit')],
    'productName' => APP_NAME,
    'productReference' => Ref.new(app_product, 'IndoorCoach Brücke.app'),
    'productType' => 'com.apple.product-type.application')
add(objects, test_target, TEST_NAME,
    'isa' => 'PBXNativeTarget',
    'buildConfigurationList' => Ref.new(list_test, "Build configuration list for PBXNativeTarget \"#{TEST_NAME}\""),
    'buildPhases' => [Ref.new(test_sources, 'Sources'), Ref.new(test_frameworks, 'Frameworks'), Ref.new(test_resources, 'Resources')],
    'buildRules' => [], 'dependencies' => [Ref.new(target_dependency, 'PBXTargetDependency')],
    'fileSystemSynchronizedGroups' => [Ref.new(tests_group, 'BridgeTests')],
    'name' => TEST_NAME, 'productName' => TEST_NAME,
    'productReference' => Ref.new(test_product, "#{TEST_NAME}.xctest"),
    'productType' => 'com.apple.product-type.bundle.unit-test')

# --- build configurations ----------------------------------------------------------------------------------------
common_app = {
  'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
  'CODE_SIGN_ENTITLEMENTS' => 'Bridge/IndoorCoachBridge.entitlements',
  'CODE_SIGN_STYLE' => 'Automatic',
  'COMBINE_HIDPI_IMAGES' => 'YES',
  'CURRENT_PROJECT_VERSION' => '1',
  'DEVELOPMENT_TEAM' => '',
  'ENABLE_HARDENED_RUNTIME' => 'YES',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'INFOPLIST_KEY_CFBundleDisplayName' => 'IndoorCoach Brücke',
  'INFOPLIST_KEY_LSApplicationCategoryType' => 'public.app-category.healthcare-fitness',
  'INFOPLIST_FILE' => 'Bridge/Info.plist',
  'INFOPLIST_KEY_LSUIElement' => 'YES',
  'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/../Frameworks'],
  'MACOSX_DEPLOYMENT_TARGET' => '15.0',
  'MARKETING_VERSION' => '0.1',
  'PRODUCT_BUNDLE_IDENTIFIER' => 'app.indoorcoach.personal.bridge',
  'PRODUCT_MODULE_NAME' => APP_NAME,
  'PRODUCT_NAME' => 'IndoorCoach Brücke',
  'SDKROOT' => 'macosx',
  'SUPPORTED_PLATFORMS' => 'macosx',
  'SWIFT_EMIT_LOC_STRINGS' => 'YES',
  'SWIFT_VERSION' => '6.0'
}
host = '$(BUILT_PRODUCTS_DIR)/IndoorCoach Brücke.app/Contents/MacOS/IndoorCoach Brücke'
common_test = {
  'BUNDLE_LOADER' => '$(TEST_HOST)',
  'CODE_SIGN_STYLE' => 'Automatic',
  'CURRENT_PROJECT_VERSION' => '1',
  'DEVELOPMENT_TEAM' => '',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/../Frameworks', '@loader_path/../Frameworks'],
  'MACOSX_DEPLOYMENT_TARGET' => '15.0',
  'MARKETING_VERSION' => '0.1',
  'PRODUCT_BUNDLE_IDENTIFIER' => 'app.indoorcoach.personal.bridge.tests',
  'PRODUCT_NAME' => '$(TARGET_NAME)',
  'SDKROOT' => 'macosx',
  'SUPPORTED_PLATFORMS' => 'macosx',
  'SWIFT_EMIT_LOC_STRINGS' => 'NO',
  'SWIFT_VERSION' => '6.0',
  'TEST_HOST' => host
}
{ app_debug => ['Debug', common_app], app_release => ['Release', common_app],
  test_debug => ['Debug', common_test], test_release => ['Release', common_test] }.each do |cid, (name, settings)|
  add(objects, cid, name, 'isa' => 'XCBuildConfiguration', 'buildSettings' => settings, 'name' => name)
end
add(objects, list_app, "Build configuration list for PBXNativeTarget \"#{APP_NAME}\"",
    'isa' => 'XCConfigurationList',
    'buildConfigurations' => [Ref.new(app_debug, 'Debug'), Ref.new(app_release, 'Release')],
    'defaultConfigurationIsVisible' => '0', 'defaultConfigurationName' => 'Release')
add(objects, list_test, "Build configuration list for PBXNativeTarget \"#{TEST_NAME}\"",
    'isa' => 'XCConfigurationList',
    'buildConfigurations' => [Ref.new(test_debug, 'Debug'), Ref.new(test_release, 'Release')],
    'defaultConfigurationIsVisible' => '0', 'defaultConfigurationName' => 'Release')

# --- project object ----------------------------------------------------------------------------------------------
find(project_obj, 'targets').value << nano(Ref.new(app_target, APP_NAME))
find(project_obj, 'targets').value << nano(Ref.new(test_target, TEST_NAME))
attrs = find(find(project_obj, 'attributes'), 'TargetAttributes')
attrs.value[Nanaimo::String.new(app_target, '')] = nano('CreatedOnToolsVersion' => '27.2')
attrs.value[Nanaimo::String.new(test_target, '')] = nano('CreatedOnToolsVersion' => '27.2', 'TestTargetID' => app_target)
_ = package_ref_id

File.write(PBXPROJ, Nanaimo::Writer::PBXProjWriter.new(plist).write)

# --- shared scheme -----------------------------------------------------------------------------------------------
def buildable(oid, product, name)
  <<~XML.chomp
    <BuildableReference
       BuildableIdentifier = "primary"
       BlueprintIdentifier = "#{oid}"
       BuildableName = "#{product}"
       BlueprintName = "#{name}"
       ReferencedContainer = "container:IndoorCoach.xcodeproj">
    </BuildableReference>
  XML
end

def indent(text, n)
  text.lines.map { |l| (' ' * n) + l }.join
end

app_ref = buildable(app_target, 'IndoorCoach Brücke.app', APP_NAME)
test_ref = buildable(test_target, "#{TEST_NAME}.xctest", TEST_NAME)
scheme = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <Scheme
     LastUpgradeVersion = "2700"
     version = "1.7">
     <BuildAction
        parallelizeBuildables = "YES"
        buildImplicitDependencies = "YES">
        <BuildActionEntries>
           <BuildActionEntry
              buildForTesting = "YES"
              buildForRunning = "YES"
              buildForProfiling = "YES"
              buildForArchiving = "YES"
              buildForAnalyzing = "YES">
  #{indent(app_ref, 14)}
           </BuildActionEntry>
        </BuildActionEntries>
     </BuildAction>
     <TestAction
        buildConfiguration = "Debug"
        selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
        selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
        shouldUseLaunchSchemeArgsEnv = "YES">
        <Testables>
           <TestableReference
              skipped = "NO">
  #{indent(test_ref, 12)}
           </TestableReference>
        </Testables>
     </TestAction>
     <LaunchAction
        buildConfiguration = "Debug"
        selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
        selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
        launchStyle = "0"
        useCustomWorkingDirectory = "NO"
        ignoresPersistentStateOnLaunch = "NO"
        debugDocumentVersioning = "YES"
        debugServiceExtension = "internal"
        allowLocationSimulation = "NO">
        <BuildableProductRunnable
           runnableDebuggingMode = "0">
  #{indent(app_ref, 9)}
        </BuildableProductRunnable>
     </LaunchAction>
     <ProfileAction
        buildConfiguration = "Release"
        shouldUseLaunchSchemeArgsEnv = "YES"
        savedToolIdentifier = ""
        useCustomWorkingDirectory = "NO"
        debugDocumentVersioning = "YES">
        <BuildableProductRunnable
           runnableDebuggingMode = "0">
  #{indent(app_ref, 9)}
        </BuildableProductRunnable>
     </ProfileAction>
     <AnalyzeAction
        buildConfiguration = "Debug">
     </AnalyzeAction>
     <ArchiveAction
        buildConfiguration = "Release"
        revealArchiveInOrganizer = "YES">
     </ArchiveAction>
  </Scheme>
XML
File.write(SCHEME, scheme)
puts "#{APP_NAME} und #{TEST_NAME} hinzugefügt."
