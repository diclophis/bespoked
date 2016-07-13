require_relative '../test_helper'

class BespokedControllerTest < MiniTest::Spec
  before do
    #TDB:
    @mock_var_lib_k8s = Dir.mktmpdir
  end

  describe "initialize" do
    it "defaults var-lib-k8s directory to a random tmp dir" do
      controller = Bespoked::Controller.new

      puts controller.inspect

      controller.var_lib_k8s.wont_equal nil

      File.writable?(controller.var_lib_k8s).must_equal true
      File.writable?(controller.var_lib_k8s_host_to_app_dir).must_equal true
      File.writable?(controller.var_lib_k8s_app_to_alias_dir).must_equal true
      File.writable?(controller.var_lib_k8s_sites_dir).must_equal true
    end

    it "allows passing a working directory" do
      controller = Bespoked::Controller.new({"var-lib-k8s" => @mock_var_lib_k8s})
      controller.var_lib_k8s.must_equal @mock_var_lib_k8s
    end
  end

  describe "ingress" do
    it "watches apiserver endpoint until it reports a new Ingress resource" do
    end

    it "writes the nginx vhost config mappings when a new Ingress resource is created" do
    end

    it "clears old nginx vhost config mappings when a existing Ingress resource is deleted" do
    end

    it "Reload nginx when changes occur" do
    end
  end
end
