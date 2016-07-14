require_relative '../test_helper'

class BespokedControllerTest < MiniTest::Spec
  before do
    @mock_var_lib_k8s = Dir.mktmpdir
    @mock_pod_name = "mock-pod"
    @mock_vhosts = [
      ["mock-x1.tld", "x1", "256.0.0.1:3001"], # x1 is a single container, on node1
      ["mock-yy.tld", "yy", "256.0.0.2:3002"], # yy is a single container, on node2
      ["mock-zz.tld", "zz", "256.0.0.1:3003"], # zz is a container with replication
      ["mock-zz.tld", "zz", "256.0.0.2:3004"]  # set to span node1 + node2
    ]
  end

  describe "initialize" do
    it "defaults var-lib-k8s directory to a random tmp dir" do
      controller = Bespoked::Controller.new

      controller.var_lib_k8s.wont_equal nil

      File.writable?(controller.var_lib_k8s).must_equal true
      File.writable?(controller.var_lib_k8s_host_to_app_dir).must_equal true
      File.writable?(controller.var_lib_k8s_app_to_alias_dir).must_equal true
      File.writable?(controller.var_lib_k8s_sites_dir).must_equal true
      File.readable?(controller.nginx_conf_path).must_equal true
      File.readable?(controller.nginx_access_log_path).must_equal true
    end

    it "allows passing a working directory" do
      controller = Bespoked::Controller.new({"var-lib-k8s" => @mock_var_lib_k8s})
      controller.var_lib_k8s.must_equal @mock_var_lib_k8s
    end
  end

  describe "install_vhosts" do
    it "creates nginx maps for routing requests to upstream pod services" do
      controller = Bespoked::Controller.new

      controller.install_vhosts(@mock_pod_name, @mock_vhosts)

      @mock_vhosts.each do |host, app, upstream|
        mapping_name = [@mock_pod_name, app].join("-")

        host_to_app_path = File.join(controller.var_lib_k8s_host_to_app_dir, mapping_name)
        app_to_alias_path = File.join(controller.var_lib_k8s_app_to_alias_dir, mapping_name)
        site_path = File.join(controller.var_lib_k8s_sites_dir, mapping_name)

        File.readable?(host_to_app_path).must_equal true
        File.readable?(app_to_alias_path).must_equal true
        File.readable?(site_path).must_equal true
      end
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
