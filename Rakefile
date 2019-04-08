PACKAGE_NAME = "hackpp"
VERSION = "0.0.3"
TRAVELING_RUBY_VERSION = "20150715-2.2.2"

desc "Package the app"
task :package => ['package:linux:x86', 'package:linux:x86_64', 'package:osx', 'package:win32']

namespace :package do
    namespace :linux do
        desc 'Package for Linux x86'
        task :x86 => "packaging/traveling-ruby-#{TRAVELING_RUBY_VERSION}-linux-x86.tar.gz" do
            create_package("linux-x86")
        end

        desc 'Package for Linux x86_64'
        task :x86_64 => "packaging/traveling-ruby-#{TRAVELING_RUBY_VERSION}-linux-x86_64.tar.gz" do
            create_package("linux-x86_64")
        end
    end
    desc 'Package for OS X'
    task :osx => "packaging/traveling-ruby-#{TRAVELING_RUBY_VERSION}-osx.tar.gz" do
        create_package("osx")
    end
    desc 'Package for Windows'
    task :win32 =>  "packaging/traveling-ruby-#{TRAVELING_RUBY_VERSION}-win32.tar.gz" do
        create_package("win32", :windows)
    end
end

file "packaging/traveling-ruby-#{TRAVELING_RUBY_VERSION}-linux-x86.tar.gz" do
    download_runtime("linux-x86")
end

file "packaging/traveling-ruby-#{TRAVELING_RUBY_VERSION}-linux-x86_64.tar.gz" do
    download_runtime("linux-x86_64")
end

file "packaging/traveling-ruby-#{TRAVELING_RUBY_VERSION}-osx.tar.gz" do
    download_runtime("osx")
end

file "packaging/traveling-ruby-#{TRAVELING_RUBY_VERSION}-win32.tar.gz" do
    download_runtime("win32")
end

def create_package(target, os_type = :unix)
    package_dir = "#{PACKAGE_NAME}-#{VERSION}-#{target}"
    sh "rm -rf #{package_dir}"
    sh "mkdir -p #{package_dir}/lib/app"
    sh "cp hackpp.rb #{package_dir}/lib/app"
    sh "mkdir #{package_dir}/lib/ruby"
    sh "tar -xzf packaging/traveling-ruby-#{TRAVELING_RUBY_VERSION}-#{target}.tar.gz -C #{package_dir}/lib/ruby"
    if os_type == :unix
        sh "cp packaging/wrapper.sh #{package_dir}/hackpp"
    else
        sh "cp packaging/wrapper.bat #{package_dir}/hackpp.bat"
    end
    if !ENV['DIR_ONLY']
        if os_type == :unix
            sh "tar -czf #{package_dir}.tar.gz #{package_dir}"
        else
            sh "zip -9r #{package_dir}.zip #{package_dir}"
        end
        sh "rm -rf #{package_dir}"
    end
end

def download_runtime(target)
    sh "cd packaging && curl -L -O --fail " \
     "https://d6r77u77i8pq3.cloudfront.net/releases/traveling-ruby-#{TRAVELING_RUBY_VERSION}-#{target}.tar.gz"
end