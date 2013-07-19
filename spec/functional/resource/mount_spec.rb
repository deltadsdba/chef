#
# Author:: Kaustubh Deorukhkar (<kaustubh@clogeny.com>)
# Copyright:: Copyright (c) 2013 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'functional/resource/base'
require 'chef/mixin/shell_out'
require 'tmpdir'

# run this test only for following platforms.
include_flag = !(['ubuntu', 'centos', 'aix'].include?(ohai[:platform]))

describe Chef::Resource::Mount, :external => include_flag do

  include Chef::Mixin::ShellOut

  # Platform specific setup, cleanup and validation helpers.

  def setup_device_for_mount
    # use ramdisk for creating a test device for mount.
    # This can cleaner if we have chef resource/provider for ramdisk.
    case ohai[:platform]
    when "aix"
      ramdisk = shell_out!("mkramdisk 16M").stdout

      # identify device, for /dev/rramdisk0 it is /dev/ramdisk0
      device = ramdisk.tr("\n","").gsub(/\/rramdisk/, '/ramdisk')

      fstype = "jfs2"
      shell_out!("mkfs  -V #{fstype} #{device}")
    when "ubuntu", "centos"
      device = "/dev/ram1"
      fstype = "tmpfs"
      shell_out!("mkfs -q #{device} 512")
    else
    end
    [device, fstype]
  end

  def cleanup_device(device)
    case ohai[:platform]
    when "aix"
      ramdisk = device.gsub(/\/ramdisk/, '/rramdisk')
      shell_out("rmramdisk #{ramdisk}")
    else
    end
  end

  # Actual tests begin here.
  before(:all) do
    @device, @fstype = setup_device_for_mount

    @mount_point = Dir.mktmpdir("testmount")
  end

  after(:all) do
    Dir.rmdir(@mount_point)
    cleanup_device(@device)
  end

  let(:new_resource) do
    new_resource = Chef::Resource::Mount.new(@mount_point, run_context)
    new_resource.device      @device
    new_resource.name        @mount_point
    new_resource.fstype      @fstype
    new_resource.options     "log=NULL" if ohai[:platform] == 'aix'
    new_resource
  end

  let(:provider) do
    provider = new_resource.provider_for_action(new_resource.action)
    provider
  end

  def current_resource
    provider.load_current_resource
    provider.current_resource
  end

  describe "testcase A: when the target state is a mounted filesystem" do
    before do
      # sanity umount for any old runs
      new_resource.run_action(:umount)
    end
    it "should mount the filesystem if it isn't mounted" do
      current_resource.enabled.should be_false
      current_resource.mounted.should be_false
      new_resource.run_action(:mount)
      new_resource.should be_updated
      current_resource.mounted.should be_true
    end
  end

  describe "testcase B: when the target state is a mounted filesystem" do
    it "should not mount the filesystem if it is mounted" do
      new_resource.run_action(:mount)
      new_resource.should_not be_updated
    end
  end

  describe "testcase C: when the filesystem should be remounted and the resource supports remounting" do
    it "should remount the filesystem if it is mounted" do
      new_resource.supports[:remount] = true
      new_resource.options     "rw,log=NULL" if ohai[:platform] == 'aix'
      new_resource.run_action(:remount)
      new_resource.should be_updated
      current_resource.mounted.should be_true
    end
  end

  describe "testcase D: when the target state is a unmounted filesystem" do
    it "should umount the filesystem if it is mounted" do
      current_resource.mounted.should be_true
      new_resource.run_action(:umount)
      new_resource.should be_updated
      current_resource.mounted.should be_false
    end
  end

  describe "testcase E: when the target state is a unmounted filesystem" do
    it "should not umount the filesystem if it is not mounted" do
      new_resource.run_action(:umount)
      new_resource.should_not be_updated
    end
  end

  describe "testcase F: when the resource supports remounting" do
    it "should not remount the filesystem if it is not mounted" do
      new_resource.supports[:remount] = true
      new_resource.run_action(:remount)
      new_resource.should_not be_updated
    end
  end

  describe "testcase G: when enabling the filesystem to be mounted" do
    it "should enable the mount if it isn't enable" do
      # setup the mount for further tests.
      new_resource.run_action(:mount)
      new_resource.run_action(:enable)
      new_resource.should be_updated
      current_resource.enabled.should be_true
    end
  end

  describe "testcase H: when enabling the filesystem to be mounted" do
    it "should enable the mount if it is enabled and mount options have changed" do
      new_resource.options     "nodev"
      new_resource.run_action(:enable)
      new_resource.should be_updated
      current_resource.enabled.should be_true
    end
  end

  describe "testcase I: when enabling the filesystem to be mounted" do
    it "should not enable the mount if it is enabled and mount options have not changed" do
      if ohai[:platform] == 'aix'
        new_resource.options     "nodev,rw"
      else
        new_resource.options     "nodev"
      end
      new_resource.run_action(:enable)
      new_resource.should_not be_updated_by_last_action
    end
  end

  describe "testcase J: when the target state is to disable the mount" do
    it "should disable the mount if it is enabled" do
      new_resource.run_action(:disable)
      new_resource.should be_updated
      current_resource.enabled.should be_false
    end
  end

  describe "testcase K: when the target state is to disable the mount" do
    # cleanup at the end
    after do
      new_resource.run_action(:umount)
    end

    it "should not disable the mount if it isn't enabled" do
      new_resource.run_action(:disable)
      new_resource.should_not be_updated
    end
  end
end
