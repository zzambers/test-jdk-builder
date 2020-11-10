#!/bin/sh

get_jdk_tag() (
    workflowtag="${1}"
    pattern='^[^/]+/([^/]+)(/.*)*$'
    if printf '%s' "${workflowtag}" | grep -q -E "${pattern}" ; then
        printf '%s' "${workflowtag}" | sed -E "s;${pattern};\\1;g"
        return 0
    else
        printf '%s' "${workflowtag}"
        return 0
    fi
    return 1
)

get_jdk_major() (
    tag="${1}"
    pattern1='^.*jdk([0-9]+)u.*$'
    if printf '%s' "${tag}" | grep -q -E "${pattern1}" ; then
        printf '%s' "${tag}" | sed -E "s;${pattern1};\\1;g"
        return 0
    fi
    pattern2='^.*jdk([0-9]+)([^0-9].*)*$'
    if printf '%s' "${tag}" | grep -q -E "${pattern2}" ; then
        printf '%s' "${tag}" | sed -E "s;${pattern2};\\1;g"
        return 0
    fi
    return 1
)

get_jdk_update() (
    tag="${1}"
    pattern='^.*jdk[0-9]+u([0-9]+)([^0-9].*)*$'
    if printf '%s' "${tag}" | grep -q -E "${pattern}" ; then
        printf '%s' "${tag}" | sed -E "s;${pattern};\\1;g"
        return 0
    fi
    return 1
)

get_jdk_build() (
    tag="${1}"
    pattern='^.*jdk[0-9]+u[0-9]+-b([0-9]+)([^0-9].*)*$'
    if printf '%s' "${tag}" | grep -q -E "${pattern}" ; then
        printf '%s' "${tag}" | sed -E "s;${pattern};\\1;g"
        return 0
    fi
    return 1
)

get_jdk_repo_type() (
    jdkmajor="${1}"
    if [ "${jdkmajor}" -lt 10 ] ; then
        printf '%s' 'hg-forest'
    elif [ "${jdkmajor}" -lt 16 ] ; then
        printf '%s' 'hg'
    else
        printf '%s' 'git'
    fi
)

set_jdk_envvars_github() (
    tag="${1}"
    jdkTag="$( get_jdk_tag "${tag}" )"
    jdkMajor="$( get_jdk_major "${jdkTag}" )"
    jdkRepoType="$( get_jdk_repo_type "${jdkMajor}" )"

    echo "JDK_TAG=${jdkTag}" >> $GITHUB_ENV
    echo "JDK_MAJOR=${jdkMajor}" >> $GITHUB_ENV
    echo "JDK_REPO_TYPE=${jdkRepoType}" >> $GITHUB_ENV
)

get_hg_commit() (
    dir="${1}"
    ref="${2}"
    cd "${dir}"
    git-hg-helper hg-rev "$( git show-ref --hash "${JDK_TAG}" )" || :
)

curl_retry() (
    archive_name="$1"
    url="$2"
    counter=0
    limit=5
    while (( counter < limit )) ; do
        if curl -f -L -o "${archive_name}" "${url}" ; then
            return 0
        fi
        sleep 10
        (( ++counter ))
    done
    return 1
)

download_repo_hg_files() (
    repoDir="openjdk-${JDK_TAG}-src"
    urlBase="https://github.com/ojdk-qa/autoupdater/releases/download/hg-files-latest/"
    if [ "${JDK_REPO_TYPE}" = 'hg-forest' ] ; then
        archive_name="hg-jdkforest-root.tar.xz"
        curl_retry "${archive_name}" "${urlBase}/${archive_name}"
        tar -xJf "${archive_name}" -C "${repoDir}"/.git
        rm -f "${archive_name}"
        rm -rf "${repoDir}"/.git/hg
        pushd "${repoDir}"
            git fetch origin refs/notes/hg:refs/notes/hg
        popd
        for subrepo in corba hotspot jaxp jaxws jdk langtools nashorn ; do
            archive_name="hg-jdkforest-${subrepo}.tar.xz"
            curl_retry "${archive_name}" "${urlBase}/${archive_name}"
            tar -xJf "${archive_name}" -C "${repoDir}/${subrepo}/.git"
            rm -f "${archive_name}"
            rm -rf "${repoDir}/${subrepo}"/.git/hg
            pushd "${repoDir}/${subrepo}"
                git fetch origin refs/notes/hg:refs/notes/hg
            popd
        done
    elif [ "${JDK_REPO_TYPE}" = 'hg' ] ; then
        archive_name="hg-hg-jdk.tar.xz"
        curl_retry "${archive_name}" "${urlBase}/${archive_name}"
        tar -xJf "${archive_name}" -C "${repoDir}"/.git
        rm -f "${archive_name}"
        rm -rf "${repoDir}"/.git/hg
        pushd "${repoDir}"
            git fetch origin refs/notes/hg:refs/notes/hg
        popd
    fi
)

generate_repo_info_file() (
    repoDir="openjdk-${JDK_TAG}-src"
    if [ "${JDK_REPO_TYPE}" = 'hg-forest' ] ; then
tee "${repoDir}/src-info.txt" << EOF
JDK_REPO_TYPE: ${JDK_REPO_TYPE}
JDK_MAJOR: ${JDK_MAJOR}
JDK_TAG: ${JDK_TAG}
JDK_HG_REV_ROOT: $( get_hg_commit "${repoDir}" "${JDK_TAG}"  )
JDK_HG_REV_CORBA: $( get_hg_commit "${repoDir}/corba" "${JDK_TAG}"  )
JDK_HG_REV_HOTSPOT: $( get_hg_commit "${repoDir}/hotspot" "${JDK_TAG}"  )
JDK_HG_REV_JAXP: $( get_hg_commit "${repoDir}/jaxp" "${JDK_TAG}"  )
JDK_HG_REV_JAXWS: $( get_hg_commit "${repoDir}/jaxws" "${JDK_TAG}"  )
JDK_HG_REV_JDK: $( get_hg_commit "${repoDir}/jdk" "${JDK_TAG}"  )
JDK_HG_REV_LANGTOOLS: $( get_hg_commit "${repoDir}/langtools" "${JDK_TAG}"  )
JDK_HG_REV_NASHORN: $( get_hg_commit "${repoDir}/nashorn" "${JDK_TAG}"  )
JDK_REV_ROOT: $( cd "${repoDir}" && git show-ref --hash "${JDK_TAG}" || : )
JDK_REV_CORBA: $( cd "${repoDir}/corba" && git show-ref --hash "${JDK_TAG}" || : )
JDK_REV_HOTSPOT: $( cd "${repoDir}/hotspot" && git show-ref --hash "${JDK_TAG}" || : )
JDK_REV_JAXP: $( cd "${repoDir}/jaxp" && git show-ref --hash "${JDK_TAG}"  || : )
JDK_REV_JAXWS: $( cd "${repoDir}/jaxws" && git show-ref --hash "${JDK_TAG}" || : )
JDK_REV_JDK: $( cd "${repoDir}/jdk" && git show-ref --hash "${JDK_TAG}"  || : )
JDK_REV_LANGTOOLS: $( cd "${repoDir}/langtools" && git show-ref --hash "${JDK_TAG}"  || : )
JDK_REV_NASHORN: $( cd "${repoDir}/nashorn" && git show-ref --hash "${JDK_TAG}"  || : )
EOF
elif  [ "${JDK_REPO_TYPE}" = 'hg' ] ; then
tee "${repoDir}/src-info.txt" << EOF
JDK_REPO_TYPE: ${JDK_REPO_TYPE}
JDK_MAJOR: ${JDK_MAJOR}
JDK_TAG: ${JDK_TAG}
JDK_HG_REV: $( get_hg_commit "${repoDir}" "${JDK_TAG}" )
JDK_REV: $( cd "${repoDir}" && git show-ref --hash "${JDK_TAG}"  || : )
EOF
elif  [ "${JDK_REPO_TYPE}" = 'git' ] ; then
tee "${repoDir}/src-info.txt" << EOF
JDK_REPO_TYPE: ${JDK_REPO_TYPE}
JDK_MAJOR: ${JDK_MAJOR}
JDK_TAG: ${JDK_TAG}
JDK_REV: $( cd "${repoDir}" && git show-ref --hash "${JDK_TAG}" )
EOF
fi
)
