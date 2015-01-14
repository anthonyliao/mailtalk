#
# Be sure to run `pod lib lint MailTalk.podspec' to ensure this is a
# valid spec and remove all comments before submitting the spec.
#
# Any lines starting with a # are optional, but encouraged
#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "MailTalk"
  s.version          = "0.14.0"
  s.summary          = "a more simplified mail library with offline caching, based on mailcore2 and inboxapp"
  s.homepage         = "https://github.com/anthonyliao/mailtalk"
  s.license          = 'MIT'
  s.author           = { "anthonyliao" => "alisforanthonyliao@gmail.com" }

  s.platform     = :ios, '8.0'
  s.requires_arc = true

  s.prefix_header_file = 'MailTalk/MailTalk/Vendors/Inbox/Inbox-Prefix.pch'
  s.source           = { :git => "https://github.com/anthonyliao/mailtalk.git", :tag => s.version.to_s }
  s.source_files = 'MailTalk/MailTalk/**/*.{h,m}'

  s.public_header_files = 'MailTalk/MailTalk/**/*.h'

  s.dependency 'gtm-oauth2', '0.1.0'
  s.dependency 'mailcore2-ios', '0.5.0'
  s.dependency 'FMDB', '2.4'
  s.dependency 'AFNetworking', '2.5.0'

  s.libraries = "sqlite3"

end
