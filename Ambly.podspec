Pod::Spec.new do |s|
  s.name                   = 'Ambly'
  s.version                = '1.2.0'
  s.license                = { :type => 'Eclipse Public License 1.0', :file => 'LICENSE' }
  s.summary                = 'ClojureScript REPL into embedded JavaScriptCore'
  s.homepage               = 'https://github.com/mfikes/ambly'
  s.author                 = 'Mike Fikes'
  s.source                 = { :git => 'https://github.com/mfikes/ambly.git', :tag => '1.2.0' }
  s.source_files           = 'ObjectiveC/src/*.{h,m}'
  s.ios.deployment_target  = '8.0'
  s.tvos.deployment_target = '9.0'
  s.osx.deployment_target  = '10.10'
  s.requires_arc           = true
  s.dependency "GCDWebServer/WebDAV", "3.3.2"
end
