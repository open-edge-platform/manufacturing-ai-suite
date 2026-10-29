import os
import time
import json
import logging
import subprocess
import sys

for handler in logging.root.handlers[:]:
    logging.root.removeHandler(handler)
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s', force=True)

# Setup paths and host IP
current_dir = os.path.dirname(os.path.abspath(__file__))
repo_path = os.path.abspath(os.path.join(current_dir, '../../../'))
sys.path.extend([current_dir, repo_path, os.path.abspath(os.path.join(current_dir, '../configs/dlsps'))])

hostIP = subprocess.check_output("ip route get 1 | awk '{print $7}'|head -1", shell=True).decode('utf-8').strip()

class utils:
    def __init__(self):
        """Initialize the utils class with the base path."""
        self.path = repo_path
        self.base_dir = f"{self.path}/industrial-edge-insights-vision"

    def json_reader(self, tc, JSON_PATH):
        """
        Read a JSON file and return the value for the given test case key.
        Args:
            tc (str): Test case key to look for
            JSON_PATH (str): Path to the JSON configuration file
        Returns:
            tuple: (key, value) if found, else None
        """
        try:
            logging.info('\n**********Reading json**********')
            with open(JSON_PATH, "r") as jsonFile:
                json_config = json.load(jsonFile)
            for key, value in json_config.items():
                if key == tc:
                    logging.info(f"Test Case: {key}\nValue: {value}")
                    return key, value
        except Exception as e:
            raise Exception(f"Failed to read JSON file: {e}")


    def docker_compose_up(self, value):
        """
        Prepare the environment and start docker compose services for the test.
        Args:
            value (dict): Dictionary containing test type and other parameters
        """
        try:
            logging.info('\n**********Setting up Docker environment**********')
            os.chdir(self.base_dir)
            if value.get("app") == "pdd":
                subprocess.check_output("cp .env_pallet-defect-detection .env", shell=True, executable='/bin/bash')
            elif value.get("app") == "pcb":
                subprocess.check_output("cp .env_pcb-anomaly-detection .env", shell=True, executable='/bin/bash')

            # Update .env file with required variables
            self._update_env_file({
                "HOST_IP": hostIP,
                "MTX_WEBRTCICESERVERS2_0_USERNAME": "test1234",
                "MTX_WEBRTCICESERVERS2_0_PASSWORD": "test1234",
                "MTX_WEBRTCICESERVERS2_0_USERNAME": "test1234", 
                "S3_STORAGE_USERNAME": "s3user", 
                "S3_STORAGE_PASSWORD": "s3pass"
            })
            
            # Run setup and start services
            logging.info('\n**********Running setup and starting services**********')
            subprocess.check_output("./setup.sh", shell=True, executable='/bin/bash')
            subprocess.check_output("docker compose up -d", shell=True, executable='/bin/bash')
            logging.info("Services started successfully")
        except Exception as e:
            raise Exception(f"Failed to start docker services: {e}")


    def _update_env_file(self, env_updates):
        """
        Update .env file with given key-value pairs.
        Args:
            env_updates (dict): Dictionary of environment variables to update
        """
        try:
            with open(".env", "r") as file:
                lines = file.readlines()
            
            with open(".env", "w") as file:
                for line in lines:
                    key = line.split("=")[0].strip()
                    if key in env_updates:
                        file.write(f"{key}={env_updates[key]}\n")
                        env_updates.pop(key)
                    else:
                        file.write(line)
                for key, value in env_updates.items():
                    file.write(f"{key}={value}\n")
        except Exception as e:
            raise Exception(f"Failed to update .env file: {e}")


    def list_pipelines(self, value,  deployment_type="docker"):
        """
        List and validate pipelines against expected configuration.
        Args:
            value (dict): Dictionary containing app type and configuration
            deployment_type (str): Deployment type, 'docker'
            
        Raises:
            Exception: If pipeline listing fails or validation errors occur
        """
        logging.info('\n\n**********List pipelines sample_list.sh**********')
        os.chdir(self.base_dir)
        
        try:
            config_paths = {
                "pdd": "apps/pallet-defect-detection/configs/pipeline-server-config.json",
                "pcb": "apps/pcb-anomaly-detection/configs/pipeline-server-config.json"
            }
            config_path = os.path.join(self.base_dir, config_paths.get(value.get("app"), config_paths["pdd"]))

            with open(config_path, 'r') as f:
                config_data = json.load(f)
                expected_pipelines = [p.get("name") for p in config_data.get("config", {}).get("pipelines", []) if p.get("name")]
                logging.info(f"Expected pipeline names: {expected_pipelines}")
            
            # Execute sample_list.sh and parse output
            try:
                output = subprocess.check_output("./sample_list.sh", shell=True, executable='/bin/bash').decode('utf-8')
                logging.info(f"sample_list.sh output: {output}")
            except subprocess.CalledProcessError as e:
                error_output = e.output.decode('utf-8') if e.output else str(e)
                raise Exception(f"Failed to execute sample_list.sh: {error_output}")
            
            if "HTTP Status Code: 200" not in output or "Loaded pipelines:" not in output:
                raise Exception("Server not reachable or pipelines information missing")
            
            pipelines_section = output.split("Loaded pipelines:")[1].strip()
            if not pipelines_section:
                raise Exception("Loaded pipelines list is empty")
            
            # Parse loaded pipeline versions
            json_start, json_end = pipelines_section.find('['), pipelines_section.rfind(']') + 1
            if json_start != -1 and json_end != 0:
                pipelines_data = json.loads(pipelines_section[json_start:json_end])
                loaded_pipeline_versions = [p['version'] for p in pipelines_data if isinstance(p, dict) and 'version' in p]
            else:
                loaded_pipeline_versions = [line.replace('-', '').strip() for line in pipelines_section.split('\n') 
                                          if line.strip() and line.startswith('-')]
            
            logging.info(f"Loaded pipeline versions: {loaded_pipeline_versions}")
            if not loaded_pipeline_versions:
                raise Exception("No pipeline versions found in server output")
            
            # Validate pipeline matching
            unmatched_versions = [v for v in loaded_pipeline_versions if v not in expected_pipelines]
            missing_names = [n for n in expected_pipelines if n not in loaded_pipeline_versions]
            matched_pipelines = [v for v in loaded_pipeline_versions if v in expected_pipelines]
            
            logging.info(f"Pipeline Name to Version Mapping ({deployment_type})")
            for name in expected_pipelines:
                status = "MATCH" if name in loaded_pipeline_versions else "MISSING"
                mapping_info = f" maps to version='{name}'" if name in loaded_pipeline_versions else " not found in loaded versions"
                logging.info(f"{status}: name='{name}'{mapping_info}")
            
            for version in unmatched_versions:
                logging.error(f"UNMATCHED: version='{version}' not found in config names")
            logging.info(f"Summary: {len(matched_pipelines)} matched, {len(unmatched_versions)} unmatched, {len(missing_names)} missing")
            
            if unmatched_versions or missing_names:
                raise Exception(f"Pipeline mismatch - Unmatched: {unmatched_versions}, Missing: {missing_names}")
            logging.info(f"SUCCESS: All pipeline versions match expected names for {deployment_type} deployment")
            logging.info("Server is reachable, and pipelines are loaded successfully")
        except Exception as e:
            logging.error(f"Error in list_pipelines: {e}")
            raise Exception(f"Pipeline listing failed: {e}")


    def start_pipeline_and_check(self, value, deployment_type="docker"):
        """
        Start a pipeline and verify it starts successfully.
        Args:
            value (dict): Dictionary containing pipeline configuration
            deployment_type (str): Deployment type, 'docker'
            
        Returns:
            str: Pipeline response ID if successful
            
        Raises:
            Exception: If pipeline start fails or server is not ready
        """
        os.chdir(self.base_dir)
        time.sleep(5)
        logging.info("Checking pipeline status with sample_status.sh before starting pipeline")

        try:
            # Check initial pipeline status
            try:
                status_output = subprocess.check_output("./sample_status.sh", shell=True, executable='/bin/bash').decode('utf-8')
            except subprocess.CalledProcessError as e:
                # Handle case where status command fails (e.g., server not ready)
                error_output = e.output.decode('utf-8') if e.output else e.stderr.decode('utf-8') if e.stderr else str(e)
                logging.warning(f"Initial status check failed (exit code {e.returncode}): {error_output}")
                status_output = "[]"  # Assume no pipelines are running
            
            logging.info(f"sample_status.sh output: {status_output}")
            if "[]" not in status_output:
                raise Exception("Pipelines are already running")
            logging.info("No pipelines are currently running - ready to start new pipeline")

            pipeline_name = value.get("pipeline")
            try:
                if pipeline_name:
                    output = subprocess.check_output(f"./sample_start.sh -p {pipeline_name}", shell=True, executable='/bin/bash')
                    logging.info(f"Using configured pipeline: {pipeline_name}")
                else:
                    output = subprocess.check_output("./sample_start.sh", shell=True, executable='/bin/bash', stderr=subprocess.STDOUT)
            except subprocess.CalledProcessError as e:
                raise e
            output = output.decode('utf-8')
            logging.info(f"sample_start.sh output: {output}")
            
            success_message = "posted successfully"
            if success_message not in output:
                raise Exception(f"Pipeline start failed. Expected message not found: '{success_message}'")
            
            if 'Response: "' in output:
                start_pos = output.find('Response: "') + len('Response: "')
                end_pos = output.find('"', start_pos)
                if end_pos != -1:
                    response_id = output[start_pos:end_pos]
                    logging.info(f"Pipeline Response ID: {response_id}")
                    logging.info("Pipeline started successfully, and response string is valid")
                    return response_id
        except Exception as e:
            logging.error(f"Error in start_pipeline_and_check: {e}")
            raise Exception
    

    def get_pipeline_status(self, value, deployment_type="docker"):
        """
        Check pipeline status and validate.
        Args:
            value (dict): Dictionary containing test configuration
        """
        logging.info('\n**********Checking pipeline status**********')
        os.chdir(self.base_dir)
        time.sleep(5)
        cmd = "./sample_status.sh"
        logging.info("Checking status for all pipelines")
        output = subprocess.check_output(cmd, shell=True, executable='/bin/bash').decode('utf-8')
        logging.info(f"Status output:\n{output}")
        if "RUNNING" not in output:
            raise Exception("No RUNNING pipelines found in output")
        logging.info("Pipeline is running")
        

    def container_logs_checker_dlsps(self, tc, value):
        """
        Check dlstreamer-pipeline-server container logs for keywords.
        Args:
            tc (str): Test case identifier
            value (dict): Dictionary containing log parameters
        Returns:
            bool: True if all keywords are found
        """
        logging.info('\n**********Checking container logs**********')
        time.sleep(5)
        container = "dlstreamer-pipeline-server"
        log_file = f"logs_{container}_{tc}.txt"
        subprocess.run(f"docker compose logs --tail=1000 {container} | tee {log_file}", shell=True, executable='/bin/bash', check=True)
        keywords = value.get("dlsps_log_param", [])
        missing_keywords = [keyword for keyword in keywords if not self.search_element(log_file, keyword)]
        if missing_keywords:
            error_msg = f"FAIL: Keywords not found in logs: {missing_keywords}"
            logging.error(error_msg)
            raise Exception(error_msg)
        logging.info("PASS: All keywords found in logs.")
        self._check_warning_messages(log_file)
        return True
        

    def _check_warning_messages(self, log_file):
        """
        Check for warning messages in DLSPS logs and report them.
        Args:
            log_file (str): Path to the log file to analyze
        Returns:
            None: Prints warning summary to console
        """
        warning_patterns = ["WARNING", "WARN", "warning", "warn", "ERROR", "Error", "error"]
        warnings_found = []
        with open(log_file, 'r', encoding='utf-8', errors='ignore') as file:
            for line_num, line in enumerate(file, 1):
                line_lower = line.lower()
                if any(pattern in line_lower for pattern in warning_patterns):
                    line_stripped = line.strip()
                    if not any(w['line'] == line_stripped for w in warnings_found):
                        warnings_found.append({'line_number': line_num, 'line': line_stripped})                 
        if warnings_found:
            logging.warning(f"⚠️  WARNING: Found {len(warnings_found)} warning message(s) in DLSPS logs:")
            print("-" * 80)
            for warning in warnings_found:
                print(f"Line {warning['line_number']} [warning]: {warning['line']}")
        else:
            print("✅ No warnings detected in logs")


    def search_element(self, logFile, keyword):
        """
        Search for a keyword in a log file.
        Args:
            logFile (str): Path to the log file
            keyword (str): Keyword to search for
        Returns:
            bool: True if keyword is found, False otherwise
        """
        keyword_found = False
        keywords_file = os.path.abspath(logFile)
        with open(keywords_file, 'rb') as file:
            for curr_line in file:
                each_line = curr_line.decode()
                print(each_line)
                if keyword in each_line:
                    keyword_found = True
        if keyword_found:
            print("✅ PASS: Keyword Found", keyword)
            return True
        else:
            print("❌ FAIL:Keyword NOT Found", keyword)
            return False


    def docker_compose_down(self):
        """
        Stop all docker compose services and verify cleanup.
        Returns:
            None: Prints cleanup status to console
        """
        os.chdir(self.base_dir)
        subprocess.check_output("docker compose down -v", shell=True, executable='/bin/bash')
        time.sleep(3)        
        try:
            subprocess.check_output("docker compose down -v", shell=True, executable='/bin/bash')
            print("✅ Docker compose down executed successfully.")
            time.sleep(3)
            print('\n**********Verifying no services are running**********')

            docker_ps_output = subprocess.check_output("docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'", shell=True, executable='/bin/bash').decode('utf-8')
            print("Current running containers:")
            print(docker_ps_output)
            lines = docker_ps_output.strip().split('\n')[1:]
            running_containers = []
            project_containers = ['dlstreamer-pipeline-server', 'prometheus', 'coturn', 'otel-collector', 'mediamtx-server', 'seaweedfs-master', 'seaweedfs-volume', 'seaweedfs-filer', 'seaweedfs-s3']
                
            for line in lines:
                if line.strip():
                    container_name = line.split('\t')[0].strip()
                    project_found = False
                    for project_name in project_containers:
                        if project_name in container_name.lower():
                            project_found = True
                            break
                    if project_found:
                        running_containers.append(container_name)
                
            if running_containers:
                print(f"⚠️ Warning: Found {len(running_containers)} project-related containers still running:")
                for container in running_containers:
                    print(f"  - {container}")
                print("These containers may need manual cleanup.")
            else:
                print("✅ No project-related containers are running.")
            print("✅ Services stopped successfully.") 
        except subprocess.CalledProcessError as e:
            raise Exception    
        

    def stop_pipeline_and_check(self, value, deployment_type="docker"):
        """
        Stop running pipelines and validate they are stopped successfully.
        Args:
            value (dict): Dictionary containing pipeline configuration
            deployment_type (str): Deployment type, 'docker'
            
        Raises:
            Exception: If pipeline stop fails or validation errors occur
        """
        logging.info("Stopping pipeline with sample_stop.sh")
        os.chdir(self.base_dir)
        
        def parse_json(output):
            start, end = output.find('['), output.rfind(']') + 1
            if start != -1 and end != 0:
                try: return json.loads(output[start:end])
                except json.JSONDecodeError: pass
            return []
        
        try:
            status_output = subprocess.check_output("./sample_status.sh", shell=True, executable='/bin/bash').decode('utf-8')
            
            # Find running pipeline ID
            running_pipeline_id = next((p.get('id') for p in parse_json(status_output) 
                                      if isinstance(p, dict) and p.get('state') == 'RUNNING'), None)
            if not running_pipeline_id:
                raise Exception("No running pipeline found to stop")
            logging.info(f"Found running pipeline ID: {running_pipeline_id}")
            
            # Execute stop command
            try:
                output = subprocess.check_output("./sample_stop.sh", shell=True, executable='/bin/bash', stderr=subprocess.STDOUT).decode('utf-8')
            except subprocess.CalledProcessError as e:
                output = e.output.decode('utf-8') if e.output else str(e)
                logging.error(f"Command returned exit code {e.returncode}")
            
            time.sleep(3)
            if value and "stopped successfully" not in output:
                raise Exception("Pipeline stop failed. Expected message not found: 'stopped successfully'")
            
            # Check final status and validate
            final_status = subprocess.check_output("./sample_status.sh", shell=True, executable='/bin/bash').decode('utf-8')
            aborted_count, running_count = final_status.count("ABORTED"), final_status.count("RUNNING")
            print(f"Status output:\n{final_status}")
            # Validate specific pipeline state
            pipeline_state = next((p.get('state') for p in parse_json(final_status) 
                                 if isinstance(p, dict) and p.get('id') == running_pipeline_id), None)
            if pipeline_state == 'ABORTED':
                logging.info(f"Pipeline {running_pipeline_id} stopped successfully")
            else:
                logging.warning(f"Pipeline {running_pipeline_id} in {pipeline_state} state, expected ABORTED")
            
            # Final validation
            if running_count > 0:
                raise Exception(f"Found {running_count} RUNNING instances - all should be ABORTED")
            if aborted_count == 0:
                raise Exception("No ABORTED instances found in status output")
            logging.info(f"All {aborted_count} pipeline instances stopped successfully")
            
        except Exception as e:
            logging.error(f"Error in stop_pipeline_and_check: {e}")
            raise
