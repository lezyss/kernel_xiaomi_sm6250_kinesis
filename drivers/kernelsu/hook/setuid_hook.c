#ifdef CONFIG_KSU_SUSFS
#include <linux/susfs_def.h>
#include <linux/workqueue.h>
extern struct work_struct susfs_extra_works;
#endif // #ifdef CONFIG_KSU_SUSFS

static __always_inline void ksu_handle_setresuid_cred(struct cred *new, const struct cred *old)
{
	if (!new || !old)
		return;

	uid_t new_uid = ksu_get_uid_t(new->uid);
	uid_t old_uid = ksu_get_uid_t(old->uid);

	// old process is not root, ignore it.
	if (unlikely(!!old_uid))
		return;

	if (IS_ENABLED(CONFIG_KSU_DEBUG))
		pr_info("handle_setresuid from %d to %d\n", old_uid, new_uid);

	// we dont have those new fancy things upstream has
	// lets just do the original thing where we disable seccomp
	if (unlikely(is_uid_manager(new_uid)))
		goto install_ksu_fd;

	if (ksu_is_allow_uid_for_current(new_uid))
		goto kill_seccomp;

#ifdef CONFIG_KSU_SUSFS
	// SuSFS: a zygote child that KSU wants umounted gets TIF_PROC_UMOUNTED, which is what the
	// SUS_PATH/SUS_MOUNT/SUS_KSTAT/SUS_MAP/OPEN_REDIRECT hooks key on. Independent of whether
	// any module is mounted (v2.3.0 semantics). Deferred extra work runs off the setuid path.
	if (is_zygote(old) && (is_isolated_process(new_uid) ||
			(is_appuid(new_uid) && ksu_uid_should_umount(new_uid)))) {
		susfs_set_current_proc_umounted();
		if (!work_pending(&susfs_extra_works))
			schedule_work(&susfs_extra_works);
	}
#endif // #ifdef CONFIG_KSU_SUSFS

	// Handle kernel umount
	ksu_handle_umount(new, old);
	return;

install_ksu_fd:
	pr_info("install fd for manager: %d\n", new_uid);
	ksu_install_fd();

kill_seccomp:
	disable_seccomp();
	set_thread_flag(TIF_KSU_MANAGED); // sucompat fast-path
	return;
}
