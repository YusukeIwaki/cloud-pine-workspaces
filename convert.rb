require 'erb'
require 'yaml'

class TemplateBinder
  def initialize(template_erb:, binding_erb:)
    evaluate_binding(binding_erb)
    @result = evaluate_template(template_erb) do |key|
      @binding_values[key]
    end
  end

  attr_reader :result

  private
  
  def content_for(key, value = nil)
    @binding_values[key] = block_given? ? yield.strip : value
  end

  def evaluate_binding(binding_erb)
    @binding_values = {}
    # binding_erbの中でcontent_forされたものが @binding_values に保持される
    binding_erb.result(binding)
  end

  def evaluate_template(template_erb)
    # template_erb の中でyieldされると、evaluate_templateに渡されたブロックが評価される。
    template_erb.result(binding)
  end
end

class DockerComposeYmlConverter
  def initialize(docker_compose_yml, name)
    @docker_compose_yml = docker_compose_yml
    @name = name
  end

  def convert_for_docker_swarm
    docker_compose_yml = YAML.load(@docker_compose_yml)
    unless docker_compose_yml["services"].key?("cloud9")
      raise ArgumentError.new("A service named 'cloud9' must be defined.")
    end

    convert_build_to_image_in_cloud9(docker_compose_yml["services"]["cloud9"])
    convert_ports_in_each_service(docker_compose_yml["services"])
    inject_networks_in_cloud9(docker_compose_yml["services"]["cloud9"])

    docker_compose_yml["networks"] ||= {}
    docker_compose_yml["networks"]["master"] = {"external" => {"name" => "cloud-pine-master"}}
    YAML.dump(docker_compose_yml)
  end

  private

  def convert_build_to_image_in_cloud9(cloud9)
    cloud9.delete("build")
    cloud9["image"] = "yusukeiwaki/cloud-pine-workspace-#{@name}"
  end

  def convert_ports_in_each_service(services)
    services.keys.each do |key|
      if services[key].key?("ports")
        services[key]["ports"].map! do |ports|
          if ports.is_a?(String)
            ports.split(":").last.to_i
          else
            ports
          end
        end
      end
    end
  end

  def inject_networks_in_cloud9(cloud9)
    cloud9["networks"] = %w(default master)
  end
end

Dir[File.dirname(__FILE__) + '/*/Dockerfile.erb'].each do |file|
  workspace_dir = File.dirname(file)
  dirname = File.basename(workspace_dir)

  dockerfile = TemplateBinder.new(
    template_erb: ERB.new(File.read('Dockerfile-c9-base.erb')),
    binding_erb: ERB.new(File.read(file))
  ).result
  File.write(File.join(workspace_dir, "Dockerfile"), dockerfile)

  docker_compose_yml = File.read(File.join(workspace_dir, "docker-compose.yml"))
  docker_compose_yml_for_swarm = 
    DockerComposeYmlConverter.new(docker_compose_yml, dirname).convert_for_docker_swarm
  File.write(File.join(workspace_dir, "docker-compose.for.swarm.yml"), docker_compose_yml_for_swarm)

  puts "docker build -t yusukeiwaki/cloud-pine-workspace-#{dirname} ./#{dirname}"
  puts "docker push yusukeiwaki/cloud-pine-workspace-#{dirname}"
end
