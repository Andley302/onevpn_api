<?php
//ERROS PHP
#error_reporting(E_ALL);
#ini_set('display_errors', '1');

if (getAuthorizationHeader() != null && check_token() != false) {
	//header('Content-Type: application/json; charset=utf-8');
	$response["ssh"] = get_ssh_users();
	$response["ovpn"] = count(get_ovpn_users());
	$response["ram_usage"] = round(get_server_memory_usage());
	$response["cpu_usage"] = round(get_server_cpu_usage());
	//$response["others_info"] = get_server_info();
	echo json_encode($response); 
}else{
	header('HTTP/1.0 403 Forbidden');
    echo "Access not allowed! ";
}

function getAuthorizationHeader(){
	$headers = null;
	if (isset($_SERVER['Authorization'])) {
		$headers = trim($_SERVER["Authorization"]);
	}
	else if (isset($_SERVER['HTTP_AUTHORIZATION'])) { //Nginx or fast CGI
		$headers = trim($_SERVER["HTTP_AUTHORIZATION"]);
	} elseif (function_exists('apache_request_headers')) {
		$requestHeaders = apache_request_headers();
		// Server-side fix for bug in old Android versions (a nice side-effect of this fix means we don't care about capitalization for Authorization)
		$requestHeaders = array_combine(array_map('ucwords', array_keys($requestHeaders)), array_values($requestHeaders));
		//print_r($requestHeaders);
		if (isset($requestHeaders['Authorization'])) {
			$headers = trim($requestHeaders['Authorization']);
		}
	}
	return $headers;
}


function get_ovpn_users() {

	$fp = fsockopen("localhost", 5555, $errno, $errstr, 30);

	if (!$fp) {
		return [];

	} else {
	    fwrite($fp, "status\n");
	
	    $data = [];
	    $do_get = false;
	    while (!feof($fp)) {
	        $get = fgets($fp, 128);
	  
	    	if( preg_match('#ROUTING TABLE#', $get ) )
	    		break;

	        if( $do_get )
	    		$data[] = $get; //trim( explode( ",", $get )[0] );

	        if( preg_match('#Common Name#i', $get ))
	        	$do_get = true;

	    }


	    fclose($fp);
	}

	return $data;
}

function get_ssh_users() {
	exec("who | wc -l", $ssh_onlines);
	return json_decode($ssh_onlines[0], true);
}

function check_token(){
	$file_token = "/root/token.api";
	if (file_exists($file_token)) {
		if (strcmp(file_get_contents($file_token), getAuthorizationHeader())){
			return true;
		}else{
			return false;
		}
	} else {
		return false;
	}
}

function get_server_memory_usage(){

    $free = shell_exec('free');
    $free = (string)trim($free);
    $free_arr = explode("\n", $free);
    $mem = explode(" ", $free_arr[1]);
    $mem = array_filter($mem);
    $mem = array_merge($mem);
    $memory_usage = $mem[2]/$mem[1]*100;

    return $memory_usage;
}

function get_server_cpu_usage(){
  $cont = file('/proc/stat');
  $cpuloadtmp = explode(' ',$cont[0]);
  $cpuload0[0] = $cpuloadtmp[2] + $cpuloadtmp[4];
  $cpuload0[1] = $cpuloadtmp[2] + $cpuloadtmp[4]+ $cpuloadtmp[5];
  sleep(1);
  $cont = file('/proc/stat');
  $cpuloadtmp = explode(' ',$cont[0]);
  $cpuload1[0] = $cpuloadtmp[2] + $cpuloadtmp[4];
  $cpuload1[1] = $cpuloadtmp[2] + $cpuloadtmp[4]+ $cpuloadtmp[5];
  return ($cpuload1[0] - $cpuload0[0])*100/($cpuload1[1] - $cpuload0[1]);

}

/*function get_server_info(){
	$script = "/root/api-getInfo.sh";
	if (file_exists($script)) {
		exec($script, $info);;
		return json_decode($info[0], true);
	} else {
		return json_decode(json_encode(""));
	}
}*/

?>