import { createSlice, PayloadAction } from '@reduxjs/toolkit';
import type {

interface ScheduledTaskState {

const initialState: ScheduledTaskState;

    setLoading(state, action: PayloadAction<boolean>) {
    },
    setError(state, action: PayloadAction<string | null>) {
    },
    setTasks(state, action: PayloadAction<ScheduledTask[]>) {
    },
    addTask(state, action: PayloadAction<ScheduledTask>) {
    },
    updateTask(state, action: PayloadAction<ScheduledTask>) {
    },
    removeTask(state, action: PayloadAction<string>) {
    },
      if (task) {
      }
    selectTask(state, action: PayloadAction<string | null>) {
    },
    setViewMode(state, action: PayloadAction<ScheduledTaskViewMode>) {
    },
    addOrUpdateRun(state, action: PayloadAction<ScheduledTaskRun>) {
    },
    setAllRuns(state, action: PayloadAction<ScheduledTaskRunWithName[]>) {
    },
    appendAllRuns(state, action: PayloadAction<ScheduledTaskRunWithName[]>) {
    },

export const {

export default scheduledTaskSlice.reducer;
