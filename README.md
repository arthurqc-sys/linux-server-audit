# Linux Server Audit

A Bash script for automated Linux server auditing. It collects system information, hardware resources, network configuration, running processes, services, user accounts, and security-related data.

The script generates a structured text report, helping system administrators identify potential security risks, review server configurations, and monitor system resources.

## Features

- **System Information:** Hostname, operating system, kernel version, uptime, and architecture.
- **Hardware & Resources:** CPU, memory, disk partitions, and swap usage.
- **Network Analysis:** Network interfaces, IP addresses, routing tables, listening ports, and DNS configuration.
- **Process & Service Monitoring:** Top CPU and memory-consuming processes, enabled services, and active services.
- **User & Security Auditing:** Interactive users, last login information, SSH configuration, and authorized SSH keys.
- **Log Analysis:** Recent system logs and SSH authentication failures.
- **Package Updates:** Checks for available package updates on supported APT-based distributions.
- **Resource Alerts:** Identifies high disk and memory usage.
- **Optional Email Delivery:** Supports sending audit reports through an externally configured email transport.

## Requirements

- Linux operating system.
- Bash.
- Root privileges or appropriate permissions for complete system information.
- Standard Linux utilities such as `hostname`, `uname`, `ip`, `ps`, `systemctl`, and `df`.

Some checks depend on additional utilities and system configurations. The script handles unavailable commands whenever possible and reports when information cannot be collected.

## Installation

Clone the repository:

```bash
git clone https://github.com/arthurqc-sys/linux-server-audit.git
```

Navigate to the project directory:

```bash
cd linux-server-audit
```

Make the script executable:

```bash
chmod +x auditoria.sh
```

## Usage

Run the audit:

```bash
sudo ./auditoria.sh
```

Or execute it directly with Bash:

```bash
sudo bash auditoria.sh
```

The script automatically generates a report named:

```text
auditoria_servidor.txt
```

### Custom Output Directory

You can specify a directory for the generated report:

```bash
sudo ./auditoria.sh /path/to/output
```

### Email Delivery (Optional)

Email delivery is optional and requires an externally configured email transport, such as `msmtp` or a compatible `sendmail` interface.

Example:

```bash
sudo AUDIT_EMAIL="recipient@example.com" ./auditoria.sh
```

The script does not automatically install or configure mail services. If no working email transport is available, the report is still generated locally.

## Audit Report

The generated report contains six main sections:

1. Machine Identification
2. Hardware and System Resources
3. Network Configuration
4. Processes and Services
5. Users and Security
6. Recent System and Authentication Logs

Additional information includes available package updates and resource usage alerts.

## Security Considerations

- Run the script with appropriate privileges to obtain more complete results.
- Review the generated report before sharing it.
- Reports may contain sensitive information, including IP addresses, hostnames, usernames, running services, and system configuration details.
- Avoid committing real audit reports or sensitive configuration files to public repositories.
- Email delivery requires a separately configured and trusted transport.

## Compatibility

Designed for Linux distributions using Bash and common system administration utilities.

The script primarily targets Debian-based distributions, including Debian, Ubuntu, and Kali Linux.

Some features may behave differently depending on the distribution, installed packages, logging system, and system configuration.

## Project Goals

This project was developed as a practical exercise in Linux system administration, Bash scripting, infrastructure auditing, and security monitoring.

It also serves as a learning project focused on infrastructure security and DevSecOps practices.

## License

This project is distributed under the MIT License. See the `LICENSE` file for details.