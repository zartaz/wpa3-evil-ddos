This script utilizes hostapd to continuously clone a WPA3 Access Point's (AP) BSSID, SSID, and channel, aiming to disrupt its service by creating an "evil twin" AP. By mimicking the legitimate AP's identifiers, clients may inadvertently connect to the malicious AP, leading to service disruption or potential data interception.​
bcs.org

Effectiveness Factors:

Transmission Power: The disruptive capability of the cloned AP heavily depends on its transmission power. A higher transmission power increases the likelihood of clients connecting to the malicious AP over the legitimate one.​

Denial-of-Service Impact: This script can induce a Denial-of-Service (DoS) effect on clients of the legitimate AP. By attracting client devices to the cloned AP, the script prevents them from maintaining stable connections with the intended network, effectively causing a DoS condition.​

Disclaimer: Deploying this script can lead to unauthorized network access and service disruption, which are illegal and unethical activities. Use this script responsibly and only in environments where you have explicit permission to conduct such testing.