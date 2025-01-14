#!/bin/sh
set -eu

PROOTIE="${PROOTIE:-prootie}"
DATA_DIR="${HOME}/.prootie"
DISTROS_DIR="${DATA_DIR}/distros"
BACKUPS_DIR="${DATA_DIR}/backups"

choose_rootfs() {
	find "${DISTROS_DIR}" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | gum choose --header="Choose a rootfs:"
}

handle_meta() {
	local_arch=$(uname -m)
	case "${local_arch}" in
	aarch64) remote_arch=arm64 ;;
	armv7a) remote_arch=armhf ;;
	x86_64) remote_arch=amd64 ;;
	i686) remote_arch=i386 ;;
	*) remote_arch="${local_arch}" ;;
	esac

	index=0
	echo "Distro,Release,Variant,Path"
	while IFS=';' read -r DISTRO RELEASE ARCH VAR TS PATH; do
		if test "${remote_arch}" = "${ARCH}" && ! test "${VAR}" = cloud && ! test "${DISTRO}" = "nixos"; then
			# echo "${DISTRO}" "${RELEASE}" "${ARCH}" "${VAR}" "${TS}" "${PATH}"
			echo "${DISTRO},${RELEASE},${VAR},${PATH}"
			index=$((index + 1))
		fi
	done
}

menu_install() {
	STR_INSTALL_FROM_FILE="Install from local file"
	lxc_mirror="$(
		gum choose \
			--header="Choose a LXC mirror:" \
			"${STR_INSTALL_FROM_FILE}" \
			https://images.linuxcontainers.org \
			https://mirrors.tuna.tsinghua.edu.cn/lxc-images \
			https://mirrors.cernet.edu.cn/lxc-images \
			https://mirrors.nju.edu.cn/lxc-images \
			https://mirrors.bfsu.edu.cn/lxc-images \
			https://mirror.lzu.edu.cn/lxc-images \
			https://mirror.nyist.edu.cn/lxc-images
	)"

	if ! test -d "${DISTROS_DIR}"; then
		mkdir -p "${DISTROS_DIR}"
	fi

	case "${lxc_mirror}" in
	"${STR_INSTALL_FROM_FILE}")
		if ! test -d "${BACKUPS_DIR}"; then
			mkdir -p "${BACKUPS_DIR}"
		fi

		file=$(gum file "${BACKUPS_DIR}")
		rootfs_name=$(gum input --placeholder="Input rootfs name.")
		case "${file}" in
		*.tar.gz)
			gzip -d <"${file}" | "${PROOTIE}" install -v "${DISTROS_DIR}/${rootfs_name}"
			;;
		*.tar.xz)
			xz -d <"${file}" | "${PROOTIE}" install -v "${DISTROS_DIR}/${rootfs_name}"
			;;
		esac
		;;
	*)
		meta="${lxc_mirror}/meta/1.0/index-user"

		dl_cmd="curl -SsLk"
		if ! command -v curl >/dev/null && command -v wget >/dev/null; then
			dl_cmd="wget -qo-"
		fi

		selection=$(${dl_cmd} -Ss "${meta}" | handle_meta | gum table --widths=10,10,10,0 --height=10)
		if [ -z "${selection}" ]; then
			exit 1
		fi

		distro=$(echo "${selection}" | cut -d',' -f1)
		release=$(echo "${selection}" | cut -d',' -f2)
		variant=$(echo "${selection}" | cut -d',' -f3)
		path=$(echo "${selection}" | cut -d',' -f4)

		rootfs=${DISTROS_DIR}/${distro}-${release}-${variant}
		rootfs=$(gum input --header="Input rootfs:" --value="${rootfs}" --placeholder="Input rootfs")
		${dl_cmd} "${lxc_mirror}${path}rootfs.tar.xz" | xz -d | "${PROOTIE}" install -v "${rootfs}"

		case "${distro}" in
		ubuntu) touch "${rootfs}/root/.hushlogin" ;;
		voidlinux) sed -i "s^root:x:0:0:root:/root:/bin/sh^root:x:0:0:root:/root:/bin/bash^g" "${rootfs}/etc/passwd" ;;
		*) ;;
		esac

		if gum confirm "Login ${rootfs} now?"; then
			${PROOTIE} login "${rootfs}"
		fi
		;;
	esac
}

menu_login() {
	rootfs="${DISTROS_DIR}/$(choose_rootfs)"
	"${PROOTIE}" login "${rootfs}"
}

menu_archive() {
	tools=""
	if command -v gzip >/dev/null; then
		tools="${tools} gzip"
	fi
	if command -v xz >/dev/null; then
		tools="${tools} xz"
	fi
	if command -v pigz >/dev/null; then
		tools="${tools} pigz"
	fi

	if ! test -d "${BACKUPS_DIR}"; then
		mkdir "${BACKUPS_DIR}"
	fi

	rootfs_name=$(choose_rootfs)
	compression_tool=$(gum choose --header="Choose a compression tool:" ${tools})

	case "${compression_tool}" in
	gzip | pigz)
		output_file="${BACKUPS_DIR}/${rootfs_name}.tar.gz"
		output_file=$(gum input --header="Input output file name:" --value="${output_file}" --placeholder="Input output file name")
		"${PROOTIE}" archive "${DISTROS_DIR}/${rootfs_name}" -v | "${compression_tool}" >"${output_file}"
		;;
	xz)
		output_file="${BACKUPS_DIR}/${rootfs_name}.tar.xz"
		output_file=$(gum input --header="Input output file name:" --value="${output_file}" --placeholder="Input output file name")
		"${PROOTIE}" archive "${DISTROS_DIR}/${rootfs_name}" -v | xz -T0 >"${output_file}"
		;;
	*) ;;
	esac

	du -ahd0 "${output_file}"
}

main() {
	menu1="install"
	menu2="login"
	menu3="archive"
	menu4="exit"

	if test "${1+1}"; then
		selected_menu=$1
	else
		selected_menu=$(gum choose \
			--header="Choose an action:" \
			"${menu1}" \
			"${menu2}" \
			"${menu3}" \
			"${menu4}")
	fi

	case "${selected_menu}" in
	"${menu1}") menu_install ;;
	"${menu2}") menu_login ;;
	"${menu3}") menu_archive ;;
	"${menu4}") exit 0 ;;
	*) ;;
	esac
}

main "$@"
