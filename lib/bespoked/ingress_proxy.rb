
class IngressProxy
  attr_accessor :run_loop

  def initialize(run_loop_in)
    self.run_loop = run_loop_in
  end

  def install(ingress_descriptions)
    puts :install
  end

  def start
    puts :start
  end

  def stop
    puts :stop
  end
end
